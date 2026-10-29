---
title: RFC 0004 System Configuration
description: >-
  How a whole PyrixOS machine is described in PyBonsai, built into one store
  path, and switched to: users, file systems, services, /etc, boot entries,
  config.pyb and lattice switch.
---

# RFC 0004 · System Configuration

<div class="pyrix-meta" markdown>
<span class="pyrix-flag">Draft</span>
<span>RFC <strong>0004</strong></span>
<span>Scope <strong>System</strong></span>
</div>

| Field | Value |
| --- | --- |
| Status | Draft, open for comment |
| Supersedes | None |
| Components | Lattice standard library (`machine` and its records), system activation, boot entries, `lattice switch`, init |

The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174) when, and only when, they appear in all capitals.

## 1. Summary

A PyrixOS machine is described by one PyBonsai file, `system.pyb`. It names the kernel, the packages, the stack of each slot, the users and groups, the file systems, the services and the files under `/etc`. Lattice builds the description into one store path, the system, and makes it a new generation of the `system` profile of RFC 0001 section 13. Switching to it updates `/etc`, users, mounts, slots and services on the running machine, and adds a boot entry, so the same generation can be chosen again from the boot menu. Rolling back is switching to an earlier generation.

## 2. Motivation

RFC 0001 builds packages and stacks and keeps them in profiles, but leaves the rest of the machine to be set up by hand. A machine set up by hand drifts: two machines given the same instructions end up different, and nobody can say exactly what one of them runs. Describing the whole machine as a derivation gives it the properties packages already have. The description is a reviewed file, two machines with the same file run the same system, and every earlier system is still in the store, ready to boot.

## 3. Goals and non-goals

| Goals | Non-goals |
| --- | --- |
| Describe users, groups, file systems, services, `/etc`, the kernel and the boot loader in PyBonsai | Partitioning and formatting disks, which the installer does once |
| Build a system into one store path, and switch to it or roll back atomically | Managing machines over the network; a description can be built and pushed with existing commands |
| Show the previous generations in the boot menu | A general module system with option merging, as in NixOS |
| Keep secrets out of the store | Boot loaders other than systemd-boot in 1.0 |
| Read the option values chosen with Trellis (RFC 0003) | Init systems other than systemd |

## 4. Terminology

System
:   The store path a system description builds to. It holds everything needed to boot and run the machine, by reference.

System description
:   The PyBonsai file, by default `/etc/pyrixos/system.pyb`, that defines the name `system` with the standard library function `machine` of section 5.

Activation
:   Bringing the running machine in line with a system, as described in section 8.

Generation
:   As in RFC 0001 section 13.1. Each generation of the `system` profile points at one system.

## 5. Describing a system

### 5.1 Standard library additions

The functions below are added to the Lattice standard library (RFC 0001 section 7.6). Every one of them except `machine` returns a read-only mapping that only `machine` reads, so a description builds its parts with ordinary PyBonsai functions and no new language features are needed.

| Function | Returns | Behaviour |
| --- | --- | --- |
| `machine(name, kernel, initrd, packages, stacks, users, groups, file_systems, services, etc, host_name, time_zone, kernel_params)` | Derivation | Declares a derivation with the builder `builtin:system` whose output, the system, has the layout of section 6. `packages` and `stacks` are passed to `profile` (RFC 0001 section 13.1). |
| `user(name, uid, group, groups, home, shell, password_file, system_user)` | Mapping | A user account. `password_file` names a file outside the store that holds a password hash (section 10). |
| `group(name, gid)` | Mapping | A group. |
| `file_system(mount_point, device, fs_type, options, needed_for_boot)` | Mapping | One mount. `device` is a path such as `/dev/disk/by-label/root` or `/dev/disk/by-uuid/...`. |
| `service(name, exec_start, user, after, wants, environment, restart, unit)` | Mapping | A systemd service. `exec_start` MUST start with a store path. `unit` holds any further `[Service]` keys as a mapping of string to string. |
| `etc_file(path, text, source, mode)` | Mapping | One file under `/etc`, given as `text` or as a derivation in `source`. `mode` is `"0444"` by default. |

Every argument except `name` has a default, so a minimal system names only its kernel, its initrd and its root file system. A name or path that cannot work, such as a user name that is not a valid login name, an `etc_file` path with `..`, or two records with the same name, fails evaluation with an error that names the record.

### 5.2 Reading Trellis options

When the directory of a system description holds a `config.pyb` written by Trellis (RFC 0003 section 9), Lattice evaluates it first, on its own, and gives its `options` mapping to the description as the read-only name `config`. When there is no such file, `config` is an empty mapping. `config.pyb` is an input of the system, so changing an option gives a new system hash. The description cannot read any other file, because PyBonsai has no imports.

### 5.3 Example

```python
def base_packages():
    return [bash, coreutils, util_linux, iproute2, nano, python3]

admins = group(name="wheel", gid=10)

alice = user(
    name="alice",
    uid=1000,
    group="users",
    groups=["wheel"],
    home="/home/alice",
    shell=f"{bash}/bin/bash",
    password_file="/etc/pyrixos/secrets/alice.hash",
)

web = service(
    name="web",
    exec_start=f"{python3}/bin/python3 -m http.server 8080",
    user="nobody",
    after=["network-online.target"],
    wants=["network-online.target"],
)

extra = [htop] if config.get("TOOLS_HTOP", False) else []

system = machine(
    name="lab-1",
    kernel=linux_6_12,
    initrd=initrd(linux_6_12, modules=["ext4", "nvme"]),
    packages=base_packages() + extra,
    stacks={"nvidia": nvidia_570},
    users=[alice],
    groups=[admins],
    file_systems=[
        file_system(mount_point="/", device="/dev/disk/by-label/root", fs_type="ext4"),
        file_system(mount_point="/boot", device="/dev/disk/by-label/ESP", fs_type="vfat"),
    ],
    services=[web],
    host_name="lab-1",
    time_zone="Europe/London",
)
```

`linux_6_12`, `initrd`, `bash` and the other packages come from the PyrixOS package set. Each name refers to a store path, so the system pins every program it runs.

## 6. Layout of a system

The output of `builtin:system` is a directory with the following entries. Every entry is a file in the output or a symlink to another store path.

| Entry | Content |
| --- | --- |
| `lattice-system.json` | The name, the host name, the records of section 5.1 in canonical JSON, and the store paths of the entries below |
| `lattice-profile.json` | Copied from `sw`, so that the slots of RFC 0001 section 13.2 work unchanged |
| `sw` | The environment that `profile` builds from `packages` and `stacks` |
| `kernel`, `initrd`, `kernel-params` | The kernel image, the initial RAM disk and the kernel command line |
| `init` | The first program of the system after the initial RAM disk (section 9.2) |
| `etc` | Every file of `/etc` that the system defines, including the generated files of section 7 |
| `units` | The systemd units of the services and mounts |
| `activate` | Records which parts of activation to run; read by Lattice, never executed |

Because the system is an ordinary derivation, `lattice plan`, `lattice check`, `lattice push` and binary caches work on it as on any package, and a machine can fetch a whole system that another machine built.

## 7. Generated files

`builtin:system` writes these files into `etc`.

| File | Written from |
| --- | --- |
| `fstab` | `file_systems`; systemd turns it into mount units at boot |
| `hostname`, `localtime` link, `locale.conf` | `host_name`, `time_zone` |
| `systemd/system/*` | `units` |
| `profile` | `PATH` with `/run/current-system/sw/bin` and each slot's `bin` (RFC 0001 section 13.4) |
| `ld.so.conf.d/lattice-stacks.conf` | Each slot's `lib` |
| `pyrixos/system-users.json` | `users` and `groups`, read by activation to write `passwd`, `group` and `shadow` (section 8.2) |

`passwd`, `group` and `shadow` are not in the store, because `shadow` holds password hashes and the store is readable by every user.

## 8. Activation

### 8.1 Order

`lattice switch` builds the system, creates a new generation of the `system` profile, and then runs these steps as root. Each step is idempotent, so running them again after a failure finishes the work.

1. Write the boot entry of the new generation (section 9.1).
2. Point `/etc/static` at the new `etc` by creating a temporary symlink and renaming it, then make every managed file in `/etc` a symlink into `/etc/static`. Files that the old system managed and the new one does not are removed. A file that was not created by Lattice is never overwritten; activation reports it and stops before step 3.
3. Update users and groups (section 8.2).
4. Mount file systems that are new and not `needed_for_boot`. A changed mount is applied at the next boot, and activation says so.
5. Switch the stack of each slot, as in RFC 0001 section 13.3.
6. Run `systemctl daemon-reload`, then stop the units that the new system removes, restart the units whose files changed, and start the units that are new.
7. Point `/run/current-system` at the system, and make the generation current by renaming the profile symlink.

If any step fails, Lattice reports the step and its error. The new generation stays in the boot menu but is not made current, so the next boot uses the generation that was current before, and `lattice rollback` restores the old `/etc`, users and services at once.

`lattice switch --boot` runs only steps 1 and 7, so the new system takes effect at the next boot. `lattice switch --test` runs steps 2 to 6 and skips the boot entry and step 7, so a reboot returns to the current generation.

### 8.2 Users and groups

The users and groups of the system description are the complete list of accounts with a login, apart from the system accounts Lattice and systemd need. Activation writes `passwd`, `group` and `shadow` atomically, through a temporary file and a rename, with these rules.

1. A user or group without a fixed number gets one from a range, 1000 to 29999 for users and 400 to 999 for system users, and keeps it. The numbers given out are recorded in `/var/lib/lattice/ids.json`, so a user removed and added again gets the same number.
2. A user removed from the description is removed from `passwd` and `shadow`. Its home directory and files are kept.
3. The password hash of each user is read from its `password_file` when activation runs. A user without one has a locked password.
4. Home directories that do not exist are created with mode `0700` and owned by the user.

### 8.3 The Lattice interface

As RFC 0001 section 6.1 requires, each operation is a method of `lattice.Lattice`, reachable through the daemon and the remote API, and the command only calls it.

| Method | Command | Operation |
| --- | --- | --- |
| `switch_system(path, mode)` | `lattice switch [--boot \| --test] [FILE]` | Evaluate the system description, build it, and activate it in the given mode |
| `rollback_system(generation)` | `lattice rollback [N]` | Make an earlier system generation current and activate it |
| `systems()` | `lattice systems` | List the system generations, with their boot entries and which one is current and which one is booted |

Only admins of the daemon (RFC 0001 section 6.2) may call these methods.

## 9. Boot

### 9.1 Boot entries

PyrixOS 1.0 boots with systemd-boot on UEFI machines. Each generation of the `system` profile gets an entry in the format of the Boot Loader Specification, type 1, in `/boot/loader/entries/pyrixos-<n>.conf`. The kernel and the initial RAM disk are copied to `/boot/pyrixos/` under names that hold their store path hashes, since the boot loader cannot read the store. A file already present is not copied again. The command line holds the system's `kernel-params` and `init=<system>/init`.

Deleting generations (RFC 0001 section 13.1) also removes their entries and any kernel or initial RAM disk in `/boot/pyrixos/` that no remaining entry uses. The current generation is the default entry.

### 9.2 Start of the system

The initial RAM disk loads the modules the root file system needs, mounts the file systems marked `needed_for_boot`, and starts the `init` given on the command line. `init` then:

1. Bind mounts `/lattice/store` read-only onto itself (RFC 0001 section 16).
2. Points `/run/current-system` and `/run/booted-system` at the system and links `/etc/static` to its `etc`, as in activation step 2.
3. Writes users and groups as in section 8.2.
4. Runs `lattice activate-boot` (RFC 0001 section 13.3).
5. Runs `systemd` from the system as process 1, which mounts the remaining file systems and starts the services.

## 10. Security considerations

The store is readable by every user and is copied to caches, so no secret may enter it. A system description refers to secrets only by paths outside the store, such as `password_file`, and activation reads them as root when it runs. Lattice MUST refuse a `password_file` or other secret path inside `/lattice/store`, and SHOULD warn when `text` of an `etc_file` looks like a private key or a password hash.

Evaluating a system description is as safe as evaluating any PyBonsai file (RFC 0001 section 7), since the description can only declare derivations and records. Activation runs as root and changes the machine, so only the daemon's admins can start it, and it acts only on the records of a system that Lattice built.

A system pins every program it runs by store path, so a change to any package gives a new system and a new boot entry. Every earlier system stays bootable until its generation is deleted, and the boot menu is the way back from a system that does not start.

## 11. Alternatives considered

The NixOS module system
:   NixOS merges option definitions from many modules with priorities and types. It is flexible but makes it hard to tell where a value came from. PyrixOS 1.0 uses plain functions instead: a description calls functions that return records, and Trellis handles options that depend on one another. A module system can be added later as a library of PyBonsai functions without changing the formats of this RFC.

Changing the machine in place with scripts
:   Rejected, because the result depends on the state the machine was in, which is the drift section 2 describes.

Image-based A and B updates
:   Writing a whole root file system image to a second partition also gives atomic updates. Store generations give the same atomicity, keep any number of earlier systems instead of one, and share unchanged files between them.

## 12. Resolved and deferred questions

Secure Boot
:   Deferred to a 1.x release. It will need signed unified kernel images built as derivations, and a key that never enters the store.

Mutable users
:   Accounts not in the description are removed from `passwd` in 1.0. An option that keeps accounts created by hand is deferred.

Boot loaders and architectures
:   systemd-boot on x86_64 UEFI only in 1.0. GRUB for BIOS machines and aarch64 are deferred.

Containers of systems
:   Running a system in a container, by starting its `init` in a namespace, is deferred.
