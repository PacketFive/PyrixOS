---
title: RFC 0005 Package Set and Images
description: >-
  How the PyrixOS package set is laid out and evaluated, how packages are
  built on the stage tools, which packages PyrixOS 1.0 ships, and how disk
  and installer images and the public binary cache are made.
---

# RFC 0005 · Package Set and Images

<div class="pyrix-meta" markdown>
<span class="pyrix-flag">Draft</span>
<span>RFC <strong>0005</strong></span>
<span>Scope <strong>Distribution</strong></span>
</div>

| Field | Value |
| --- | --- |
| Status | Draft, open for comment |
| Supersedes | None |
| Components | PyBonsai (functions shared between files), Lattice (package sets, `builtin:closure`, store registration), the package set, images, the public binary cache |

The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174) when, and only when, they appear in all capitals.

## 1. Summary

The package set is a directory of PyBonsai files in the PyrixOS repository. Lattice evaluates its files in name order, and each file sees the names the files before it define, so the set is split into readable layers without an import statement. A system description sees the names of the whole set. Every package is built with the stage tools of RFC 0002 through one function, `build`, which runs the usual configure, build and install steps in the sandbox. PyrixOS 1.0 ships the packages needed to boot, log in, reach the network, edit files and run Lattice itself. Images are ordinary derivations: a disk image holds one system and its store, and the installer image is a disk image whose system installs another one. Continuous integration builds both and boots them in a virtual machine, and a public binary cache serves every path the package set builds.

## 2. Motivation

RFC 0004 lets a description name `bash` or `linux_6_12`, but says only that these names come from "the PyrixOS package set". PyBonsai has no imports, by design (RFC 0001 section 7), so a description cannot load a file of packages, and one file holding the whole distribution would be hard to review. The bootstrap package set already shows the shape of a package description; it needs a common way to build a package, a way to share that across files, and a way to turn a system into something a machine can boot.

## 3. Goals and non-goals

| Goals | Non-goals |
| --- | --- |
| Split the package set into files without adding imports to PyBonsai | A general module or overlay system |
| Build every package from source with the stage tools, through one function | Packages for desktops, graphics or sound in 1.0 |
| Ship a base system that boots, logs in, networks and runs Lattice | Architectures other than x86_64 |
| Build bootable disk and installer images as derivations, in the sandbox | ISO images; the installer is a raw disk image for USB sticks and virtual machines |
| Test the images by booting them in continuous integration | Testing on physical machines in continuous integration; one physical machine is tested by hand for each release |
| Serve the whole package set from a signed public cache | A cache that accepts uploads from users |

## 4. Terminology

Package set
:   The directory `pkgs/` of the PyrixOS repository, and the names its files define.

Layer
:   One file of the package set. A layer sees the names of the layers before it.

Stage tools
:   As in RFC 0002: the stage 3 compiler, linker, C library, shell and core utilities.

Closure
:   A store path and every store path it refers to at run time, directly or indirectly (RFC 0001 section 11).

## 5. The package set

### 5.1 Layers

The package set is a directory. Each file whose name ends in `.pyb` is a layer, and layers are evaluated in the order of their names, compared as bytes. The names start with two digits so that the order is plain:

| Layer | Contents |
| --- | --- |
| `00-bootstrap.pyb` | The seed and stages 1 to 3 of RFC 0002, unchanged |
| `10-stdenv.pyb` | `build`, `python_package`, `rust_package` and the other functions every later layer uses (section 5.3) |
| `20-base.pyb` | Libraries and command line programs |
| `30-toolchains.pyb` | Python, Rust and the build tools later packages need, such as Meson and Ninja |
| `40-system.pyb` | Linux, firmware, systemd, `initrd` and Lattice |
| `90-images.pyb` | `disk_image`, `installer_image` and the systems they hold (section 8) |

A layer is evaluated with the Lattice standard library and every top-level name of the layers before it, including functions. A name a layer defines MUST NOT repeat a name of an earlier layer or of the standard library; evaluation fails and names both places. A name that starts with `_` is private to its layer and is not passed on. Each layer is evaluated once per evaluation of the set, so a package defined in `20-base.pyb` is one derivation, whichever later layer uses it.

PyBonsai 1.2 makes this possible: a host name may hold a function defined by an earlier evaluation, and an error inside that function names the file and line where the function is defined. The function keeps its own closure, so a layer can call a function of an earlier layer but cannot reach names the earlier layer did not define.

### 5.2 Reaching the package set

The setting `system.package_set` names the package set directory, by default `/etc/pyrixos/pkgs`. When it exists, Lattice evaluates the set before a system description and gives the description every public name of the set, as if they were standard library names. `lattice eval`, `lattice build` and the other commands that take a file accept `--package-set DIR` to do the same for any file. As with `config.pyb` (RFC 0004 section 5.2), a client of the daemon reads the layers and sends their text, and the daemon never reads a file named by its caller.

The package set is versioned with the PyrixOS repository. A machine updates it by checking out a newer revision into `/etc/pyrixos/pkgs`; the installer writes the revision it was built from. Because every package is a derivation, a system pins the whole package set: two machines with the same revision and the same description get the same system store path.

### 5.3 The standard environment

`10-stdenv.pyb` defines the functions that build packages. All of them call `derivation` with the stage 3 shell as the builder, so they add nothing to the standard library.

| Function | Builds |
| --- | --- |
| `build(name, version, src, inputs, configure_flags, make_flags, phases, outputs)` | A package with the steps `unpack`, `patch`, `configure`, `build`, `check`, `install` and `fixup`. Each step is a shell fragment with a default for the GNU build system; `phases` replaces any of them. |
| `meson_build(...)`, `cmake_build(...)` | The same, with the configure and build steps of Meson and Ninja or of CMake |
| `python_package(name, version, src, inputs)` | A Python package from its source distribution, built into a wheel with `pip` without network access and installed into `$out` |
| `rust_package(name, version, src, crates, inputs)` | A Rust program or library, with `crates` the list of crates of its `Cargo.lock` fetched by checksum and given to Cargo as a vendored directory |
| `patch_file(src, patch)` | A source tree with a patch applied |

The `fixup` step strips debugging symbols into a `debug` output when the package declares one, rewrites the `#!` lines of scripts to name programs by store path, and fails the build if an output refers to a path of the seed or of stages 1 and 2, the same check stage 3 makes (RFC 0002 section 6). Programs are linked against the stage 3 C library with its store path as the run path, so they never read `/lib` or `/usr/lib`.

Every source is fetched with `fetch_url` and its SHA-256 digest. A Rust crate is fetched from crates.io with the checksum its `Cargo.lock` records, which is the SHA-256 digest of the `.crate` file. The script `tools/cargo-lock-to-pyb` turns a `Cargo.lock` into the PyBonsai list of crates, so that the list is reviewed as source and not read at evaluation time.

## 6. Packages of PyrixOS 1.0

| Group | Packages |
| --- | --- |
| Toolchain | GCC, Binutils, glibc and Make from stage 3; pkg-config, Autoconf, Automake, Libtool, Bison, Flex, gperf, Meson, Ninja, CMake |
| Core | Bash, coreutils, util-linux, findutils, diffutils, grep, sed, gawk, tar, gzip, xz, bzip2, zstd, less, file, which, procps-ng, psmisc, kmod, shadow without PAM, e2fsprogs, dosfstools, mtools |
| Libraries | zlib, OpenSSL, libffi, libxcrypt, libcap, libseccomp, ncurses, readline, expat, SQLite, libxml2, acl, attr |
| System | Linux 6.12 LTS, linux-firmware for common network adapters, systemd with systemd-boot, networkd, resolved and logind, dbus-broker, `initrd` (section 7.2) |
| Network | iproute2, iputils, OpenSSH, curl, ca-certificates, nftables |
| Languages | Python 3.12 with pip, Rust from mrustc (section 6.1), Perl for the builds that need it |
| Lattice | PyBonsai, Cloche, Trellis and Lattice with their Python dependencies: Pydantic, pydantic-core, typing-extensions, annotated-types, cryptography, cffi and pycparser |
| Editors | nano, vim |

### 6.1 Rust

pydantic-core and cryptography are written partly in Rust, and Lattice needs both. RFC 0002 builds languages other than C and C++ with the stage tools, so PyrixOS builds Rust without a Rust binary: mrustc, a Rust compiler written in C++, is built with the stage 3 GCC and compiles the Rust compiler of the newest version it supports. That compiler builds the next version, and so on up to the version the package set uses. Each step is a derivation, and only the last one is used by packages. The chain takes several hours to build, and the public cache holds every step.

## 7. Kernel and boot

### 7.1 Linux

The kernel is Linux 6.12, the long-term release whose source stage 1 already fetches for its headers. Its configuration starts from `x86_64_defconfig` and adds the fragments in `pkgs/kernel/`, one file per concern: `base` (systemd's requirements, cgroup version 2, namespaces, seccomp, EFI stub), `storage` (NVMe, virtio, ext4, vfat, xfs), `network` (common Ethernet and wireless adapters, nftables) and `virt` (KVM and virtio for the microVM backend). `make olddefconfig` merges them, and the build fails if an option a fragment sets is missing from the result, so a fragment cannot be silently dropped. Modules are installed into the kernel's output, which `kmod` and the slots of RFC 0001 section 13 find by store path.

### 7.2 Initial RAM disk

`initrd(kernel, modules)` builds a `newc` archive with a static BusyBox and a short `init` script. The script loads `modules` and their dependencies from the kernel's output, waits for the device of the file system mounted at `/`, which the kernel command line names with `root=` (RFC 0004 section 9.1), mounts it and the file systems marked `needed_for_boot`, and runs `switch_root` to the `init=` program of the system. BusyBox is built from the source that the seed rebuild already uses (RFC 0002 section 8). A systemd-based initial RAM disk is deferred.

## 8. Images

### 8.1 Closures

An image must hold the closure of its system, which only Lattice knows, since references are found after a build (RFC 0001 section 11). The standard library function `closure(drv)` declares a derivation with the builder `builtin:closure`. Lattice builds `drv` first, then writes two files outside the sandbox, as it does for `builtin:unpack`:

| File | Content |
| --- | --- |
| `paths` | Every store path of the closure of the outputs of `drv`, one per line, sorted |
| `registration.json` | For each of those paths, its references, content hash and size, in the format `lattice export-registration` writes |

The output depends only on `drv` and on the contents of its closure, so it is reproducible whenever the closure is.

### 8.2 Disk images

`disk_image(system, size_mib, label)` builds a raw disk image with a GUID partition table, an EFI system partition of 512 MiB and an ext4 root partition, without loop devices or root privileges, so it builds in the sandbox:

1. The root file system is laid out in a directory: the closure of `system` under `lattice/store`, `registration.json` under `lattice/var`, the `system` profile with `system` as generation 1, and `/etc/pyrixos/pkgs` holding the package set.
2. `mkfs.ext4 -d` turns the directory into a file system image with fixed timestamps, a fixed UUID derived from the system's hash and a fixed hash seed.
3. The EFI system partition is made with `mkfs.vfat` and filled with `mcopy`: systemd-boot as `EFI/BOOT/BOOTX64.EFI`, and the kernel, initial RAM disk and loader entry that RFC 0004 section 9.1 would write.
4. `sfdisk` writes the partition table into the image file, and the two file systems are copied into place.

At the first boot, `lattice activate-boot` finds `registration.json` and an empty store database, registers every path and the root of generation 1, and removes the file. From then on the machine is an ordinary PyrixOS machine, and `lattice switch` adds generation 2.

The image of the same system and package set is the same file on every machine. `lattice build --check` tests this for each release.

### 8.3 Installer image

The installer image is a disk image whose system boots to a console with the command `pyrixos-install`. It holds, in its store, the closure of a default system as well as its own, so it installs without a network. `pyrixos-install DISK [DESCRIPTION]`:

1. Partitions `DISK` as in section 8.2 and makes the file systems, after asking for confirmation unless `--yes` is given.
2. Copies the package set and the description, by default a copy of `pkgs/systems/default.pyb` with the host name and the first user asked for, to `/etc/pyrixos` on the target.
3. Runs `lattice switch` with the settings `store.root` and `system.root` pointing at the mounted target, which builds or copies the system into the target's store and activates it there with the offline system manager of RFC 0004, and writes systemd-boot with `bootctl install --root`.

Paths missing from the installer's store are fetched from the public cache when the network is available, and built otherwise.

## 9. Continuous integration and the public cache

The package set is built by a builder machine run by the project, which pushes every path to the public cache (RFC 0001 section 14) with the key `cache.pyrixos-1`. The cache is a directory published over HTTPS; its URL and public key are written into the default settings of the images. The builder records SLSA provenance for every path, and the images set `require_provenance = true`.

Continuous integration of the PyrixOS repository evaluates the whole package set on every change, and for every change to `pkgs/` builds the disk and installer images with the public cache as a substituter, so only changed paths are built. It then boots each image in QEMU with OVMF, without a network for the disk image, and passes when the system reaches `multi-user.target`, a login works on the serial console and, for the installer image, `pyrixos-install --yes` installs to a second virtual disk that boots in turn. A change that builds something the cache does not hold and that takes longer than the time limit of the CI runner fails, and is built by the builder machine first.

## 10. Security considerations

A layer is an ordinary PyBonsai file and is evaluated with the same rules as any other (RFC 0001 section 7). Sharing functions between layers gives a later layer no new capability: a function runs in the scope it was defined in, and the standard library is the same for every layer.

The package set is trusted code for the machine that uses it, in the same way a description is, because it decides what the system runs. It is reviewed in the PyrixOS repository, and `/etc/pyrixos/pkgs` is writable only by root.

`registration.json` lets the first boot register paths without checking their signatures, because the image itself was the unit of trust. Images are signed with the release key, and their digests are published with each release. `lattice activate-boot` MUST check that every path in `registration.json` has the content hash it lists before it registers the path.

The Rust compiler is built from mrustc rather than downloaded, so the trust placed in the binary seed of RFC 0002 is the only binary trust in the distribution.

## 11. Alternatives considered

Imports in PyBonsai
:   An import statement for `.pyb` files would make the order of evaluation depend on what files ask for, and would let a file reach any other file. Layers keep a fixed, visible order and need only one change to PyBonsai.

One file for the whole package set
:   Simple to evaluate, but a single file of several thousand lines is hard to review, and every change touches the same file.

Downloading a Rust binary
:   Quicker by hours, but it adds a second binary that the distribution trusts. The mrustc chain is built once and served from the cache.

An ISO installer
:   An ISO needs `xorriso` and a second boot path for El Torito. A raw disk image boots from a USB stick on every UEFI machine and in every virtual machine, and needs no extra tools. ISO images may follow in 1.x.

A systemd initial RAM disk
:   More capable, but larger, and it ties the first stage of boot to the whole of systemd. A BusyBox `init` of a few dozen lines is enough to mount `/` in 1.0.

## 12. Resolved and deferred questions

Package versions
:   Resolved: the package set holds one version of each package. A second version, such as a second Linux series, is a separate name such as `linux_6_6`.

Secure Boot
:   Deferred, as in RFC 0004.

Graphics and desktops
:   Deferred to 1.x.

aarch64
:   Deferred; it needs its own seed (RFC 0002).
