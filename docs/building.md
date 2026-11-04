# Building PyrixOS and the binary cache

PyrixOS is built by a builder machine run by the project. The builder keeps one Lattice store, builds the images on every change to `main`, boots them in QEMU, and pushes what it built to a binary cache on the builder, signed with the key `cache.pyrixos-1` (RFC 0005 section 9). The images are published as the assets of GitHub releases. Until the project has a public host for the cache, the cache serves the project's own machines, and anyone else who wants one runs their own from the same scripts.

The workflow `.github/workflows/ci.yml` has three jobs:

| Job | Runs on | Does |
| --- | --- | --- |
| `evaluate` | A GitHub-hosted runner, for every push and pull request | Checks that each `config.pyb` matches its `defconfig` and evaluates every description under `pkgs/systems` |
| `images` | The builder, a self-hosted runner, for pushes to `main` and manual runs | Builds the disk, virtual machine, installer, live, netboot and WSL images. Boots the disk image, the qcow2, vhdx and vdi disks, the live ISO as a CD, as a USB disk and with BIOS, and the netboot files over PXE. Checks the WSL root file system, installs from the installer image, and pushes the systems to the cache |
| `images-cross` | The builder, as `images`, once for riscv64 and once for aarch64 | Builds the disk image and the U-Boot firmware, boots the disk image with UEFI and with U-Boot, and pushes the system and the firmware to the cache |

A GitHub-hosted runner has too little disk and time for the bootstrap, so the `images` and `images-cross` jobs need the builder. They run only when the repository variable `PYRIXOS_BUILDER` is `true`, and never for a pull request, so code from a fork never runs on the builder.

## Setting up the builder

These steps are done once, on the builder machine and on GitHub.

1. Install QEMU, OVMF, the `qemu-efi-riscv64` and `qemu-efi-aarch64` firmware, `qemu-user-static` for riscv64 and aarch64, xz, the GitHub CLI `gh`, and Lattice with Trellis. `qemu-user-static` registers QEMU with `binfmt_misc` with the `F` flag, which the build sandbox needs (RFC 0006 section 5); `qemu-user-binfmt` registers it without that flag. The sandbox also needs unprivileged user namespaces, which Ubuntu 24.04 restricts by default (see [Build Sandbox](components/sandbox.md)):

    ```sh
    sudo apt install qemu-system-x86 qemu-system-misc qemu-system-arm ovmf \
        qemu-efi-riscv64 qemu-efi-aarch64 qemu-user-static xz-utils gh
    echo 'kernel.apparmor_restrict_unprivileged_userns=0' | sudo tee /etc/sysctl.d/60-pyrixos-userns.conf
    sudo sysctl --system
    sudo usermod -aG kvm "$USER"
    sudo install -d -o "$USER" /opt/pyrixos-builder
    python3 -m venv /opt/pyrixos-builder/venv
    /opt/pyrixos-builder/venv/bin/pip install pyrixos-lattice trellis-kconfig
    export PATH=/opt/pyrixos-builder/venv/bin:$PATH
    lattice backend-status
    ```

    The boot tests need `/dev/kvm`, hence the `kvm` group, which takes effect at the next login. `grep flags /proc/sys/fs/binfmt_misc/qemu-riscv64` should show `F`, and `lattice backend-status` should print `namespaces: available`.

2. Generate the signing key on the builder. The secret key never leaves the machine:

    ```sh
    sudo install -d -m 700 -o "$USER" /etc/lattice/keys
    lattice generate-key cache.pyrixos-1 /etc/lattice/keys/cache.pyrixos-1.sec
    ```

    The command prints the public key, `cache.pyrixos-1:` followed by base64 text. Clients of the cache need it.

3. Write the settings file of the builder's store, for example `/etc/lattice/builder.toml`. The store needs about 150 GB for the three architectures:

    ```toml
    [store]
    root = "/var/lib/pyrixos-builder"
    max_jobs = 8

    [cache]
    secret_key_file = "/etc/lattice/keys/cache.pyrixos-1.sec"
    ```

4. On GitHub, under *Settings*, *Actions*, *Runners*, add a self-hosted Linux x64 runner on the builder with the extra label `pyrixos-builder`, and install it as a service that runs as the user who owns the store.
5. Under *Settings*, *Secrets and variables*, *Actions*, set these repository variables:

    | Name | Value |
    | --- | --- |
    | `PYRIXOS_BUILDER` | `true`, which turns the `images` and `images-cross` jobs on |
    | `LATTICE_SETTINGS` | The settings file of step 3 |
    | `STORE_ROOT` | The store root of that file, such as `/var/lib/pyrixos-builder` |
    | `CACHE_DIR` | The cache directory the jobs push to after each build of `main`, by default `/var/tmp/pyrixos-cache` |

## Watching the builder

`gh run watch` and the run page on GitHub show each job and step as it runs. To see what the builder is compiling, run `scripts/builder-watch.sh` on the builder as the user of the runner. It lists each running `lattice build` and the derivations it is building, with how long each has been running. With `log`, it follows the output of the running job, as the GitHub log shows it:

    ssh -t builder 'watch -n 5 /opt/pyrixos-builder/PyrixOS/scripts/builder-watch.sh'
    ssh -t builder /opt/pyrixos-builder/PyrixOS/scripts/builder-watch.sh log

The boot tests keep the serial console of each machine. The jobs upload them as the artifacts `console-logs`, `console-logs-riscv64` and `console-logs-aarch64`:

    gh run download RUN_ID -R PacketFive/PyrixOS -n console-logs

## The local cache

`scripts/publish-cache.sh` builds the derivations it is given and pushes each output, with its whole closure, to the directory `CACHE_DIR`. Each file is followed by the derivations to build, and `--` separates files:

```sh
SETTINGS=/etc/lattice/builder.toml CACHE_DIR=/srv/pyrixos-cache \
  scripts/publish-cache.sh pkgs/systems/default.pyb system -- pkgs/systems/installer.pyb system
```

`lattice push` skips paths the cache already holds, so the directory grows run by run. The cache is a directory of static files: a signed JSON entry and a provenance file for each store path, and the compressed archives under `archive/`. Lattice on the builder reads it as `file:///srv/pyrixos-cache`, and other machines on the same network read it over HTTP once a web server serves the directory, for example nginx, or for a quick test:

```sh
cd /srv/pyrixos-cache && python3 -m http.server 8080
```

A client trusts the cache with these lines in its Lattice settings, `/etc/lattice/settings.toml` on a PyrixOS machine:

```toml
substituters = ["http://builder.lan:8080"]
trusted_keys = ["cache.pyrixos-1:..."]
require_provenance = true
```

Every entry is signed and every archive is checked against the hash in its entry, so plain HTTP on a local network does not let anyone change what a client installs. A path signed with another key, or changed after it was signed, is refused.

## Releasing images

The official PyrixOS images are published on the [releases page](https://github.com/PacketFive/PyrixOS/releases) of this repository, and only the project maintainers create those releases, from the project's builder. Anyone else can build the same images with the same script, keep them locally, or publish them in a repository of their own.

`scripts/release-images.sh` builds the images of the architectures it is given, boots each disk image in QEMU, installs a system from the x86_64 installer image, and writes the release assets with their `SHA256SUMS`:

```sh
SETTINGS=/etc/lattice/builder.toml STORE_ROOT=/var/lib/pyrixos-builder \
  scripts/release-images.sh 0.1.0 x86_64 riscv64 aarch64
```

| Asset | Contents | Use |
| --- | --- | --- |
| `pyrixos-VERSION-ARCH.img.xz` | The disk image | Decompress and write to a disk, or boot in QEMU |
| `pyrixos-installer-VERSION-x86_64.img.xz` | The installer disk image | Write to a USB stick and boot it to install |
| `pyrixos-live-VERSION-x86_64.iso` | The live ISO image | Boot from a CD or, written as it is, from a USB stick, with UEFI or BIOS |
| `pyrixos-netboot-VERSION-x86_64.tar.xz` | The kernel, the initial RAM disk, the root file system as `root.cpio`, `ipxe.efi` and `boot.ipxe` | Serve over TFTP and HTTP to boot over PXE |
| `pyrixos-VERSION-x86_64.qcow2.xz`, `.vhdx.xz`, `.vdi.xz` | The disk image for QEMU, Hyper-V and VirtualBox | Decompress and attach to a virtual machine |
| `pyrixos-wsl-VERSION-x86_64.tar.gz` | The WSL root file system | `wsl --import PyrixOS C:\WSL\PyrixOS pyrixos-wsl-VERSION-x86_64.tar.gz` |
| `pyrixos-u-boot-VERSION-ARCH.tar.xz` | U-Boot for riscv64 and aarch64 boards without UEFI firmware | See RFC 0006 |
| `SHA256SUMS` | The SHA-256 digest of every asset | `sha256sum -c --ignore-missing SHA256SUMS` |

Disk images are mostly empty space, so xz makes them small: the 4.8 GB x86_64 disk image becomes about 190 MB. A GitHub release asset must be smaller than 2 GiB, and the script stops if one is not. The assets go to `/var/tmp/pyrixos-release/VERSION`, or to `OUT`. With `UPLOAD=1`, the script uploads them with `gh` to a draft prerelease with the tag `vVERSION` in the repository `REPO`, and a maintainer publishes it after a last look. `REPO` is `PacketFive/PyrixOS` by default, which only maintainers can write to. To publish your own build, set `REPO` to a repository you own, such as a fork, and say in its release notes that the images are not official PyrixOS releases.

## Running your own cache

Anyone can build PyrixOS and run a cache for their own machines with the same steps as the builder: install Lattice, generate a key with a name of their own, such as `cache.example-1`, name it in the settings, and run `scripts/publish-cache.sh`. Every package is built from source from the published seed (RFC 0002), so a cache built elsewhere holds the same store paths as the project's, and a machine can trust both keys at once.

## A public cache

When the project has a host for the cache, the builder copies `CACHE_DIR` to it after each push. Any host that serves static files over HTTPS will do, and nothing on the host runs PyrixOS code. GitHub suits neither use: Pages limits a site to 1 GB and a file to 100 MB, and a release holds at most 1000 assets, fewer than the store paths of one system.

| Host | Copied with |
| --- | --- |
| Cloudflare R2, Backblaze B2 or Azure Blob Storage, behind a CDN with a custom domain | `rclone` or, for S3 interfaces, `s3` |
| Amazon S3 with CloudFront | `s3` |
| A server with nginx | `rsync` over SSH |

Three more steps turn it on:

1. Set the URL as the default of `CACHE_URL` and the public key as the default of `CACHE_KEY` in `pkgs/Kconfig`, the same values as the fallbacks of `config.get("CACHE_URL", ...)` and `config.get("CACHE_KEY", ...)` in `pkgs/95-systems.pyb`, and regenerate the configurations:

    ```sh
    for arch in riscv64 aarch64; do
      trellis --kconfig pkgs/Kconfig --defconfig pkgs/systems/$arch/defconfig \
        --config pkgs/systems/$arch/config.pyb olddefconfig
    done
    ```

    Every system built afterwards has `/etc/lattice/settings.toml` with the cache as a substituter, its key as the only trusted key, and `require_provenance = true`. While either option is empty, systems are built without that file.

2. Configure the copying tool on the builder, for example with `rclone config`.
3. Set the repository variables `CACHE_SYNC` (`rclone`, `s3` or `rsync`) and `CACHE_DEST` (such as `remote:pyrixos-cache`, `s3://pyrixos-cache` or `cache@host:/srv/cache`), with `S3_ENDPOINT` and the secrets `CACHE_ACCESS_KEY_ID` and `CACHE_SECRET_ACCESS_KEY` for `s3`. The `images` and `images-cross` jobs copy the cache only while `CACHE_DEST` is set.

`scripts/publish-cache.sh` copies the archives before the entries that name them and deletes nothing, so a machine reading the cache during a copy never finds an entry whose archive is missing.
