---
title: RFC 0006 Architectures, Image Formats and Boot Loaders
description: >-
  How the PyrixOS package set builds for RISC-V 64 and ARM64 as well as
  x86_64, which image formats PyrixOS publishes, and which boot loaders
  start them.
---

# RFC 0006 · Architectures, Image Formats and Boot Loaders

<div class="pyrix-meta" markdown>
<span class="pyrix-flag">Draft</span>
<span>RFC <strong>0006</strong></span>
<span>Scope <strong>Distribution</strong></span>
</div>

| Field | Value |
| --- | --- |
| Status | Draft, open for comment |
| Supersedes | The x86_64 only non-goal of RFC 0005 section 3 |
| Components | Lattice 0.13 (`config` in package set layers, kernel image names), Trellis (`pkgs/Kconfig`), Cloche 1.2 (riscv64 system call filter), the package set, images, boot loaders |

The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174) when, and only when, they appear in all capitals.

## 1. Summary

The package set builds for one architecture at a time, chosen by the Trellis option `ARCH`. The layers of the set see the same `config` as the file built with them, and a table in `00-bootstrap.pyb` holds every value that differs between architectures. The x86_64 seed builds stages 1 and 2 as a cross build for the target, and stage 3 onward runs on the target, through `binfmt_misc` emulation on an x86_64 builder or natively on target hardware. RISC-V 64 comes first and ARM64 second. PyrixOS publishes raw disk images, hybrid ISO images, network boot files, virtual machine disks and a WSL root file system, started by systemd-boot on UEFI, by GRUB on BIOS, and by U-Boot on boards without UEFI firmware.

## 2. Motivation

RFC 0005 builds an x86_64 system and boots it in QEMU with UEFI firmware. Most of the package set does not depend on the architecture, but a few values do: the target triple, the name of the dynamic linker, the kernel configuration and image, the UEFI file names and the GPT type of the root partition. RISC-V boards and ARM64 servers, boards and virtual machines are common targets for a small, reproducible distribution, and users expect the image formats other distributions publish: an ISO for USB sticks and optical media, disks for Hyper-V, VirtualBox and QEMU, network boot files and a WSL distribution.

## 3. Goals and non-goals

| Goals | Non-goals |
| --- | --- |
| Build the whole package set for x86_64, RISC-V 64 and ARM64 from one set of files | 32-bit architectures |
| Keep every x86_64 derivation unchanged by the work | A platform field in derivations (section 11) |
| Start every architecture from the one published seed | A seed per architecture before the target has been built once |
| Build on an x86_64 machine through emulation, and on target hardware natively, with the same outputs | Cross compiling every package |
| Publish raw, ISO, network boot, virtual machine and WSL images | Cloud provider images in 1.0 |
| Boot through UEFI with systemd-boot, BIOS with GRUB, and boards with U-Boot | Secure Boot with a signed shim in 1.0 |

## 4. Selecting the architecture

### 4.1 The option

`pkgs/Kconfig` is a Trellis option tree (RFC 0003). Its choice `Target architecture` has the members `ARCH_X86_64`, `ARCH_RISCV64` and `ARCH_AARCH64`, and the string option `ARCH` holds the name the package set reads: `x86_64`, `riscv64` or `aarch64`. A directory of descriptions for one architecture holds a `defconfig` with the choice, and `trellis olddefconfig` writes its `config.pyb`:

```
trellis --kconfig pkgs/Kconfig --defconfig pkgs/systems/riscv64/defconfig \
  --config pkgs/systems/riscv64/config.pyb olddefconfig
```

### 4.2 Layers see `config`

Lattice 0.13 evaluates the layers of a package set with the same `config` as the file built with them, the `options` of the `config.pyb` next to that file (RFC 0004 section 5.2). The layers of RFC 0005 section 5.1 are unchanged in number and order. Lattice keeps the names of the last set it evaluated for one set and one `config`, so files in one directory share one evaluation of the set. A file whose directory holds no `config.pyb` gets an empty `config`, and the set builds for x86_64.

### 4.3 The table of architectures

`00-bootstrap.pyb` defines `ARCH`, read with `config.get("ARCH", "x86_64")`, and `ARCHITECTURES`, a dictionary with one entry per architecture. `TARGET_INFO` is the entry of `ARCH`, and later layers read it.

| Key | x86_64 | riscv64 | aarch64 |
| --- | --- | --- | --- |
| `TARGET` | `x86_64-pyrix-linux-gnu` | `riscv64-pyrix-linux-gnu` | `aarch64-pyrix-linux-gnu` |
| `loader` | `ld-linux-x86-64.so.2` | `ld-linux-riscv64-lp64d.so.1` | `ld-linux-aarch64.so.1` |
| `native` | `x86_64-pc-linux-gnu` | `riscv64-unknown-linux-gnu` | `aarch64-unknown-linux-gnu` |
| `gcc_lib` | Edit `i386/t-linux64` | None | Edit `aarch64/t-aarch64-linux` |
| `kernel_arch` | `x86` | `riscv` | `arm64` |
| `kernel_config` | `x86_64_defconfig` | `defconfig` | `defconfig` |
| `kernel_image` | `arch/x86/boot/bzImage` | `arch/riscv/boot/Image` | `arch/arm64/boot/Image` |
| `efi`, `efi_boot` | `x64`, `BOOTX64.EFI` | `riscv64`, `BOOTRISCV64.EFI` | `aa64`, `BOOTAA64.EFI` |
| `root_type` | `4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709` | `72EC70A6-CF74-40E6-BD49-4BDA08E8F224` | `B921B045-1DF0-41C3-AF44-4C6F280D3FAE` |
| `perl`, `openssl` | `x86_64-linux-thread-multi`, `linux-x86_64` | `riscv64-linux-thread-multi`, `linux64-riscv64` | `aarch64-linux-thread-multi`, `linux-aarch64` |
| `llvm`, `rust` | `X86;ARM;AArch64`, `x86_64-unknown-linux-gnu` | `RISCV`, `riscv64gc-unknown-linux-gnu` | `AArch64;ARM`, `aarch64-unknown-linux-gnu` |

RISC-V 64 uses the `rv64gc` instruction set and the `lp64d` ABI, the defaults of GCC for `riscv64-*-linux`. The root partition types are those of the [Discoverable Partitions Specification](https://uapi-group.org/specifications/specs/discoverable_partitions_specification/).

Build scripts name the values that differ with `@ARCH@`, `@LOADER@`, `@NATIVE@`, `@GCCLIB@`, `@EFI@`, `@EFIBOOT@` and `@ROOTTYPE@`, and the function `for_target` replaces them. `package` in `00-bootstrap.pyb` applies it to every bootstrap script, and the image and installer layers apply it to theirs. Python code in a layer reads `TARGET_INFO` directly. For x86_64 every script MUST come out byte for byte as before, so that no x86_64 derivation changes; the change that introduced the table was checked by evaluating every public derivation of the set before and after it.

### 4.4 Kernel images

Lattice links the `kernel` of a system to `bzImage` in the kernel output, or to `Image` when there is no `bzImage`, which is the file riscv64 and arm64 kernels build. Both carry the EFI stub, so systemd-boot starts them the same way.

## 5. Bootstrapping a new architecture

### 5.1 Stages

The seed runs on x86_64. The stages of RFC 0002 are already a cross bootstrap: stage 1 builds a cross toolchain for `TARGET` with the seed, stage 2 cross compiles temporary tools that run on `TARGET`, and stage 3 rebuilds everything natively with stage 2. For riscv64 and aarch64 nothing in the stages changes except the values of section 4.3:

| Stage | Runs on | For riscv64 or aarch64 |
| --- | --- | --- |
| Stage 1 | x86_64, with the seed | The cross toolchain for `riscv64-pyrix-linux-gnu`; the kernel headers get `ARCH` from the environment |
| Stage 2 | x86_64 for the cross compiled tools, the target for Bison and Python | Temporary tools that run on the stage 1 glibc for the target |
| Stage 3 and later layers | The target | Every package, built natively |

The stage 3 audit of RFC 0002 section 6 applies unchanged: nothing in stage 3 may name a path of stage 1 or 2.

### 5.2 Emulation

On an x86_64 builder, the programs of the target run through QEMU user mode, registered with `binfmt_misc`. The registration MUST have the `F` flag and name a static QEMU, because the build sandbox has its own mount namespace and no host libraries; the kernel then opens the interpreter when the registration is made and uses it in any namespace. On Debian and Ubuntu the package `qemu-user-static` registers it this way:

```
$ cat /proc/sys/fs/binfmt_misc/qemu-riscv64
enabled
interpreter /usr/libexec/qemu-binfmt/riscv64-binfmt-P
flags: POF
```

The sandbox does not change: QEMU runs as an x86_64 process, so the x86_64 system call filter of Cloche applies to the system calls it makes. On target hardware the builder runs natively with the filter of the target (section 10).

Emulation is slow. The stages and the base layer take hours on a 12 core builder. The Rust chain of RFC 0005 section 6.1 would take days, and no system needs it, since the Python packages of Lattice are pure Python. The public cache (RFC 0005 section 9) is where users get the target binaries; builders on target hardware SHOULD rebuild them and compare outputs, since the outputs of an emulated and a native build MUST be the same.

### 5.3 A seed for the target

`seed_archive` builds the next seed for `SEED_TARGET`, `{ARCH}-linux-musl`. Built with `ARCH` set to `riscv64`, it is a riscv64 seed with the layout of RFC 0002 section 5.2, and it lets a riscv64 machine start the bootstrap without x86_64. Publishing it is a later step; until then, every architecture starts from the one x86_64 seed, which keeps the trusted base to one archive.

## 6. Image formats

Every image is a derivation, built in the sandbox from a system's closure as in RFC 0005 section 8. The table lists what PyrixOS publishes for each release:

| Format | File | Made by | For | Architectures |
| --- | --- | --- | --- | --- |
| Raw disk | `.img` | `disk_image` | USB sticks, SD cards, QEMU, real disks | All |
| Installer disk | `.img` | `installer_system` with `disk_image` | Installing to another disk | All |
| Hybrid ISO | `.iso` | `iso_image`, with `xorriso` | Optical media, USB sticks, virtual machines; boots on UEFI and BIOS | All; BIOS on x86_64 only |
| Network boot | iPXE, kernel, `initrd`, SquashFS root in a second `initrd`, iPXE script | `netboot_files` | UEFI PXE boot over TFTP | All |
| QEMU | `.qcow2` | `qemu-img convert` | QEMU and libvirt | All |
| Hyper-V | `.vhdx` | `qemu-img convert` | Hyper-V generation 2 machines (UEFI) | x86_64, aarch64 |
| VirtualBox | `.vdi`, `.ova` | `qemu-img convert`, OVF descriptor | VirtualBox with EFI | x86_64 |
| WSL | `.tar.gz` root file system | `wsl_rootfs` | `wsl --import`; systemd enabled through `/etc/wsl.conf` | x86_64, aarch64 |
| Board firmware | `u-boot.bin`, and `fw_dynamic.bin` of OpenSBI on riscv64 | `uboot_firmware` | Machines whose firmware is not UEFI, with the raw disk; QEMU `virt` first | riscv64, aarch64 |
| Board image | `.img` with U-Boot | `board_image` | Boards that load U-Boot from their boot medium, when one can be tested | riscv64, aarch64 |

A live ISO and the installer share the system of RFC 0005 section 8.3. The ISO holds an EFI system partition image for UEFI, GRUB for BIOS on x86_64, and the root file system as SquashFS, mounted read-only with a `tmpfs` overlay. GRUB's configuration on the ISO is written from the systemd-boot entry of the same image, so both boot paths start the same kernel, initial RAM disk and command line; GRUB's MBR starts it from a USB stick and its El Torito image from optical media. Network boot serves the same live system: the firmware loads iPXE, which loads the kernel, the initial RAM disk and a second archive holding `/live/root.squashfs`, and the command line gives `root=live:initrd`, so the initial RAM disk mounts the SquashFS file it already holds. A WSL root file system has no kernel and no boot loader; `/etc/wsl.conf` turns systemd on, and the root account is set as the default user. Virtual machine disks are conversions of the raw disk, so every format of one release holds the same system store path. A machine without UEFI firmware boots the raw disk too: OpenSBI and U-Boot are loaded by the machine, QEMU's `-bios` and `-kernel` for `virt`, and U-Boot's UEFI support starts systemd-boot from the EFI system partition, so no boot entry is written for U-Boot. A board that reads U-Boot from its SD card or eMMC needs it written at a fixed place of the disk, which `board_image` will do for each board that is tested.

## 7. Boot loaders

| Loader | Firmware | Architectures | Writes it |
| --- | --- | --- | --- |
| systemd-boot | UEFI | All | `lattice` boot entries (RFC 0004 section 9), as in RFC 0005 |
| GRUB | BIOS, and the BIOS path of the ISO | x86_64 | A GRUB writer of boot entries, added to Lattice next to the systemd-boot one |
| U-Boot | Boards without UEFI firmware | riscv64, aarch64 | U-Boot's UEFI support starts systemd-boot from the EFI system partition; `extlinux.conf` is the fallback for boards whose U-Boot has no UEFI |
| OpenSBI | RISC-V machine mode, before U-Boot or EDK2 | riscv64 | Part of the board image or of the firmware |

On UEFI the removable media path, `EFI/BOOT/` with the file name of section 4.3, is used, so an image boots without firmware variables. Secure Boot needs a signed shim and a key that never enters the store (RFC 0004 section 12); it stays deferred to a 1.x release.

## 8. Testing

`scripts/boot-test.sh` and `scripts/install-test.sh` boot images in QEMU and require the system state `running` with no failed units. The test machine depends on the architecture:

| Architecture | QEMU | Machine | Firmware |
| --- | --- | --- | --- |
| x86_64 | `qemu-system-x86_64` | `q35`, KVM when available | OVMF |
| riscv64 | `qemu-system-riscv64` | `virt` | EDK2 `RISCV_VIRT_CODE.fd` with OpenSBI, or OpenSBI and U-Boot `qemu-riscv64_smode` |
| aarch64 | `qemu-system-aarch64` | `virt`, `-cpu max` | EDK2 `QEMU_EFI.fd`, or U-Boot `qemu_arm64` |

Every image of section 6 has a test: the ISO boots on UEFI and, on x86_64, on BIOS; the raw disk of riscv64 and aarch64 boots on U-Boot as well as on EDK2; the network boot files boot through QEMU's built-in TFTP and iPXE; converted disks are checked with `qemu-img check` and the qcow2 disk boots; the WSL root file system is unpacked and its `init` checked.

## 9. Order of work

| Step | Work | Done when |
| --- | --- | --- |
| 1 | `ARCH` in Lattice and the package set, x86_64 unchanged | Every x86_64 derivation keeps its store path |
| 2 | riscv64 stages 1 to 3 | `bootstrap_tests` passes for riscv64 |
| 3 | riscv64 base, system and Python layers | A riscv64 raw disk boots to `running` in QEMU with EDK2 |
| 4 | Lattice in the riscv64 system | The riscv64 test image passes the boot test |
| 5 | aarch64, steps 2 to 4 again | The aarch64 test image passes the boot test |
| 6 | ISO, network boot, virtual machine and WSL images | Each passes its test of section 8 |
| 7 | GRUB for BIOS, U-Boot board images | A BIOS ISO boot on x86_64 and a U-Boot boot of riscv64 in QEMU |

The formats of step 6 can be built for x86_64 in parallel with steps 2 to 5.

## 10. Security considerations

On an emulated builder, QEMU user mode runs every target program of the build, so it is part of what the builder trusts, as the kernel is. A fault in it could change an output without changing its store path. Rebuilding on target hardware and comparing outputs (section 5.2) detects that, and the public cache records the builder of every path in its provenance (RFC 0005 section 9).

The `F` flag makes the kernel keep the interpreter open from the time of registration, so a program in the sandbox cannot replace it, and the sandbox gains no host file.

Cloche's system call filter (RFC 0001 section 9.4) has a table for each machine it runs builds on. Cloche 1.2 adds riscv64, with audit architecture `AUDIT_ARCH_RISCV64`, `0xC00000F3`, and the system call numbers of the generic table of the kernel, which are those of aarch64. On a machine without a table, Cloche reports its backends unavailable rather than build without a filter.

Images for other architectures carry the same root account rules as RFC 0005 section 10.

## 11. Alternatives considered

| Alternative | Why not |
| --- | --- |
| A `system` or platform field in every derivation, as in Nix | It would change the store path of every existing derivation, and the architecture is already part of each one through its builder and inputs |
| A package set directory per architecture, with a layer that sets `ARCH` and links to the others | The order of layers would depend on file names chosen to sort first, and every new layer would need a link in each directory |
| Cross compiling every package from x86_64 | Many build systems do not cross compile well, and the outputs would differ from those of a native build on the target |
| Building a riscv64 seed first and starting the stages from it under emulation | Stages 1 and 2 would run emulated for no gain; the x86_64 seed already cross builds them |

## 12. Open questions

| Question | Current answer |
| --- | --- |
| Which RISC-V and ARM64 boards get board images | QEMU `virt` first; boards follow when a maintainer can test them |
| Whether the ISO root is SquashFS or EROFS | SquashFS, the format GRUB and every kernel read |
| How to build the Rust chain of the `RUST` option for riscv64 and aarch64 | On target hardware or a native builder, served from the cache; a cross built rustc is a later option |
