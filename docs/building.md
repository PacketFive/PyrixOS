# Building PyrixOS and the binary cache

PyrixOS is built by a builder machine run by the project. The builder keeps one Lattice store, builds the images on every change to `main`, boots them in QEMU, and publishes what it built to the public binary cache, signed with the key `cache.pyrixos-1` (RFC 0005 section 9). Machines that run PyrixOS fetch from that cache instead of building, and reject any path without a valid signature and signed provenance.

The workflow `.github/workflows/ci.yml` has two jobs:

| Job | Runs on | Does |
| --- | --- | --- |
| `evaluate` | A GitHub-hosted runner, for every push and pull request | Checks that each `config.pyb` matches its `defconfig` and evaluates every description under `pkgs/systems` |
| `images` | The builder, a self-hosted runner, for pushes to `main` and manual runs | Builds the disk, installer, live and WSL images, boots the disk image, installs from the installer image, and publishes the systems to the cache |

A GitHub-hosted runner has too little disk and time for the bootstrap, so the `images` job needs the builder. It runs only when the repository variable `PYRIXOS_BUILDER` is `true`, and never for a pull request, so code from a fork never runs on the builder.

## Choosing the cache host

The cache is a directory of static files: a JSON entry and a provenance file for each store path, and the compressed archives under `archive/`. Any host that serves files over HTTPS can serve it, and nothing on the host runs PyrixOS code. The builder writes the cache to a local directory and copies it to the host with `scripts/publish-cache.sh`.

| Host | Copied with | Notes |
| --- | --- | --- |
| Cloudflare R2 with a custom domain | `rclone` or `s3` | No charge for downloads. The suggested choice. |
| Backblaze B2 behind Cloudflare | `rclone` or `s3` | No charge for downloads served through Cloudflare. |
| Amazon S3 with CloudFront | `s3` | Charges for downloads. |
| A server with nginx | `rsync` over SSH | Needs a TLS certificate and someone to run the server. |

GitHub Pages and release assets do not fit: Pages limits a site to 1 GB and a file to 100 MB, and the archives of one system already take more.

## Setting up the builder

These steps are done once, on the builder machine and on GitHub.

1. Install QEMU, OVMF, `binfmt_misc` support for riscv64 and aarch64, and the tool that copies to the host (`rclone`, the `aws` CLI or `rsync`). Configure the tool for the host on the builder, for example with `rclone config` for a remote named `r2`.
2. Generate the signing key on the builder. The secret key never leaves the machine:

    ```sh
    sudo install -d -m 700 /etc/lattice/keys
    sudo lattice generate-key cache.pyrixos-1 /etc/lattice/keys/cache.pyrixos-1.sec
    ```

    The command prints the public key, `cache.pyrixos-1:` followed by base64 text. Keep it for step 5.

3. Name the key in the settings file the builder's store uses:

    ```toml
    [store]
    root = "/var/lib/pyrixos-builder"
    max_jobs = 8

    [cache]
    secret_key_file = "/etc/lattice/keys/cache.pyrixos-1.sec"
    ```

4. On GitHub, under *Settings*, *Actions*, *Runners*, add a self-hosted Linux x64 runner on the builder with the extra label `pyrixos-builder`, and install it as a service that runs as the user who owns the store.
5. Set the default cache of the images in `pkgs/Kconfig`: the URL as the default of `CACHE_URL` and the public key from step 2 as the default of `CACHE_KEY`. Set the same values as the fallbacks of `config.get("CACHE_URL", ...)` and `config.get("CACHE_KEY", ...)` in `pkgs/95-systems.pyb`, which descriptions without a `config.pyb` use, and regenerate the configurations:

    ```sh
    for arch in riscv64 aarch64; do
      trellis --kconfig pkgs/Kconfig --defconfig pkgs/systems/$arch/defconfig \
        --config pkgs/systems/$arch/config.pyb olddefconfig
    done
    ```

    Every system built afterwards has `/etc/lattice/settings.toml` with the cache as a substituter, its key as the only trusted key, and `require_provenance = true`. While either option is empty, systems are built without that file.

6. Under *Settings*, *Secrets and variables*, *Actions*, set these repository variables, and the secrets if the host needs them:

    | Name | Kind | Value |
    | --- | --- | --- |
    | `PYRIXOS_BUILDER` | Variable | `true`, which turns the `images` job on |
    | `LATTICE_SETTINGS` | Variable | The settings file of step 3 |
    | `STORE_ROOT` | Variable | The store root of that file, such as `/var/lib/pyrixos-builder` |
    | `CACHE_DIR` | Variable | The local cache directory, by default `/var/tmp/pyrixos-cache` |
    | `CACHE_SYNC` | Variable | `rclone`, `s3` or `rsync` |
    | `CACHE_DEST` | Variable | Where to copy the cache, such as `r2:pyrixos-cache`, `s3://pyrixos-cache` or `cache@host:/srv/cache`. Publishing is skipped while it is empty. |
    | `S3_ENDPOINT` | Variable | The S3 endpoint, for `s3` with a host other than Amazon S3 |
    | `CACHE_ACCESS_KEY_ID`, `CACHE_SECRET_ACCESS_KEY` | Secrets | Write credentials, for `s3` |

## Publishing by hand

The same script publishes from a shell on the builder. Each file is followed by the derivations to build, and `--` separates files:

```sh
SETTINGS=/etc/lattice/builder.toml SYNC=rclone CACHE_DEST=r2:pyrixos-cache \
  scripts/publish-cache.sh pkgs/systems/default.pyb system -- pkgs/systems/installer.pyb system
```

`lattice push` publishes each path with its whole closure and skips paths the cache already holds. The script copies the archives before the entries that name them and deletes nothing, so a machine reading the cache during a copy never finds an entry whose archive is missing.

## Checking the cache

On any machine with Lattice, fetch a path with a settings file that trusts only the published key:

```toml
substituters = ["https://cache.pyrixos.org"]
trusted_keys = ["cache.pyrixos-1:..."]
require_provenance = true
```

```sh
lattice --settings check.toml substitute /lattice/store/...-default
lattice --settings check.toml verify /lattice/store/...-default
```

A path signed with another key, or changed after it was signed, is refused.
