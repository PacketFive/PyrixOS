---
title: RFC 0002 Bootstrap
description: >-
  How PyrixOS builds its first tools: a small binary seed fetched by SHA-256,
  stage builds of a C toolchain and core tools from source in the sandbox,
  and a rebuild of the seed that checks it.
---

# RFC 0002 · Bootstrap

<div class="pyrix-meta" markdown>
<span class="pyrix-flag">Draft</span>
<span>RFC <strong>0002</strong></span>
<span>Scope <strong>Bootstrap</strong></span>
</div>

| Field | Value |
| --- | --- |
| Status | Draft, open for comment |
| Supersedes | None |
| Components | Lattice standard library (`unpack`), bootstrap seed, stage descriptions in the package set |

The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174) when, and only when, they appear in all capitals.

## 1. Summary

The build sandbox holds only the store paths a derivation names (RFC 0001 section 9.2), so the first derivation that compiles anything needs a compiler that is already in the store. PyrixOS gets it from a bootstrap seed: one archive of statically linked programs, fetched with a fixed SHA-256 digest and unpacked into the store. Every other program in the distribution, including the compiler that builds it, is built from source in the sandbox, in stages that start from the seed. The last stage builds the seed again from source, and a release of the seed is published only when that rebuild gives the same archive, byte for byte.

## 2. Motivation

A distribution that downloads its compiler as a binary trusts whoever built that binary. PyrixOS cannot remove that trust in 1.0, but it can make it small, fixed and checkable:

1. The seed is one file with one digest, written in the PyBonsai source of the distribution, so a change to it is a visible change to a reviewed file.
2. Nothing in the installed system links to or runs from the seed. The seed only builds the next stage.
3. The seed can be rebuilt by anyone from source with the stage tools, and from any other compiler, and compared with the published archive.

## 3. Goals and non-goals

| Goals | Non-goals |
| --- | --- |
| Build the whole of PyrixOS 1.0 for x86_64 from source, starting from one binary seed | A full-source bootstrap from a few hundred bytes of machine code, which is planned after 1.0 (section 11) |
| Keep the seed small, statically linked and free of references to the host | Other architectures in 1.0; aarch64 follows with its own seed |
| Make every stage reproducible, so two machines get the same store paths and contents | Bootstrapping languages other than C and C++ from their own seeds; they are built with the stage tools |
| Let anyone check the seed by rebuilding it | Building the seed on hosts other than Linux |

## 4. Terminology

Seed
:   The archive of statically linked programs that enters the store by digest, and the store path it is unpacked to.

Stage
:   A set of derivations built only with the tools of the stage before it.

Stage tools
:   The output of the last stage: the compiler, linker, C library, shell and core utilities that every package of the distribution is built with. Package descriptions receive them as `stdenv`.

Fixed point
:   The state in which building the seed from the stage tools gives the seed that the stages started from.

## 5. The seed

### 5.1 Contents

The programs of the seed MUST be statically linked, and the seed MUST NOT need a file outside itself. Its programs find their own files relative to their location, so it works at any store path.

| Part | Purpose |
| --- | --- |
| BusyBox | Shell, core utilities, `sed`, `awk`, `grep`, `find`, `diff`, `patch`, `tar`, `gzip`, `xz` decompression |
| GNU Make | Running the build systems of stage 1 |
| GNU Binutils | Assembler, linker and archive tools |
| GCC with C and C++ | A compiler that targets `x86_64-linux-musl` |
| musl | The C library of that compiler, as a static library and as a shared library that is also its program loader |

The programs of stage 1 are linked against the shared musl of the seed. Each one names the loader and library directory of the seed by its store path (`-Wl,-dynamic-linker` and `-Wl,-rpath`), so it runs in any sandbox that has the seed as an input and in no other. The compiler of the seed still names `/lib/ld-musl-x86_64.so.1` as its default loader, and configure scripts link test programs without the flags above, so every build that uses the seed links that name to the loader of the seed in its own sandbox root.

Seed 0 takes GCC 11.2.1, Binutils 2.37 and musl from the native x86_64 toolchain of musl.cc (`x86_64-linux-musl-native.tgz`, SHA-256 `eb1db6f0f3c2bdbdbfb993d7ef7e2eeef82ac1259f6a6e1757c33a97dbcef3ad`), and adds BusyBox 1.36.1 and GNU Make 4.4.1 built statically with that compiler. It unpacks to 245 MB and the archive is 58 MB. Later seeds are built by `seed-archive` (section 8) from the versions of the stage 3 packages at the time of the release. A newer seed is needed only when a stage 1 package can no longer be built with the old one.

### 5.2 Archive format

The seed is a tar archive compressed with xz. Entries MUST be in sorted order, with owner and group 0, modification time equal to `SOURCE_DATE_EPOCH`, and no device files, setuid or setgid bits. Symbolic links MUST be relative and MUST stay inside the archive. These rules make the archive a pure function of its contents, which section 8 depends on.

### 5.3 Fetching and unpacking

The seed is declared in PyBonsai with `fetch_url` and a fixed digest, and unpacked with a new standard library function.

| Function | Returns | Behaviour |
| --- | --- | --- |
| `unpack(archive)` | Derivation | Declares a derivation with the builder `builtin:unpack` whose output is the content of `archive`, a derivation that produces one file. The name is the name of `archive` without the `.tar`, `.tar.gz` or `.tar.xz` ending. Lattice unpacks the file itself, outside the sandbox, because before the seed no program exists in the store that could do it. |

Since `builtin:unpack` runs in Lattice and not in the sandbox, it MUST refuse an archive that would write outside its output: entries with absolute names or `..` components, links that point outside the output, device files and FIFOs. It MUST clear setuid, setgid and sticky bits and write permission for group and others, and MUST NOT follow a link it has written. An archive that breaks any of these rules fails the build with an error that names the entry. The output then becomes read-only in the store like any other (RFC 0001 section 10).

```python
seed = unpack(fetch_url(
    url="https://github.com/PacketFive/PyrixOS/releases/download/seed-0/pyrix-seed-0.tar.xz",
    sha256="fb88d1cf923f3f02c520015ab06bd5c2d6276fe9b7917a976b7e35a64124ea1c",
))
```

Each seed is published as an asset of a release of the PyrixOS repository whose tag is the name of the seed, and is also kept in the public binary cache so that one site going away does not stop a bootstrap.

## 6. Stages

Each stage is an ordinary set of derivations in the package set. A derivation in a stage MUST name only tools from the stage before it, the sources it fetches with `fetch_url`, and other derivations of its own stage.

| Stage | Built with | Produces | Purpose |
| --- | --- | --- | --- |
| 0 | Nothing | `seed` | The unpacked seed |
| 1 | Seed | Bash, coreutils, sed, grep, gawk, diffutils, findutils, GNU m4, bison and Python, linked against the musl of the seed; Binutils and GCC with C and C++ as a cross compiler for `x86_64-pyrix-linux-gnu`; Linux kernel headers; glibc and libstdc++ built with that cross compiler | A toolchain that targets glibc without using any part of the host or the seed at run time of its output |
| 2 | Stage 1 | Bash, coreutils, m4, gawk, sed, grep, diffutils, findutils, tar, gzip, xz, bzip2, patch, GNU Make, Binutils and GCC, cross compiled to run on the glibc of stage 1; then bison and Python, built by that GCC | Temporary native tools |
| 3 | Stage 2 | Kernel headers, glibc, Binutils, GCC and Bash, built by stage 2; then coreutils, m4, gawk, sed, grep, diffutils, findutils, tar, gzip, xz, bzip2, patch and GNU Make, built by the GCC of stage 3 | The stage tools, `stdenv`, with no reference to stage 2, stage 1 or the seed |

Stage 3 builds glibc, Binutils and GCC again so that the stage tools are built by a compiler that was itself built from source by PyrixOS. Lattice already records the store paths each output refers to (RFC 0001 section 11). The closure of the stage 3 outputs MUST be checked against that record, and the package set MUST fail to build if it holds a path of the seed, of stage 1 or of stage 2. The first build of the stages found five kinds of such reference, and the package set removes each one:

| Reference | Cause | Fix |
| --- | --- | --- |
| Debug information of glibc, Binutils and GCC | The stage 2 compiler writes the include directories of stages 1 and 2 into it | Their debug information is removed after install |
| `zgrep` of gzip | It records the path of `grep` found at configure time | `GREP=grep` |
| `diff` of diffutils | It records the path of `pr` | Built with the stage 3 coreutils |
| `updatedb` of findutils | It records the path of `sort` | Built with the stage 3 coreutils |
| `fixincl` of GCC | It records the path of `sed` | The tools that rerun fixincludes are removed |

### 6.1 Build environment of the stages

The sandbox gives a build no `/bin/sh` and sets `PATH` to a directory that does not exist (RFC 0001 section 9.5). Every stage derivation therefore starts with the same short script: it sets `PATH` from the `path` value of its environment, which lists the `bin` directories of its inputs, and links `/bin/sh`, `/bin/bash` and `/usr/bin/env` in the sandbox root to programs of its inputs, because many build systems call them by those names. Builds that use the seed compiler also get the loader link of section 5.1. These links exist only in the sandbox of that build and are not part of any output.

The bootstrap builds no manuals, and every `make` runs with `MAKEINFO=true`, so no stage needs Texinfo. Perl is not needed either: the kernel headers, glibc, Binutils and GCC build without it.

Compilers in stages 1 to 3 do not search `/usr/include` or `/lib`. Each stage instead has small wrapper scripts, written as derivations, that call the real compiler with the glibc and kernel header directories of that stage (`-idirafter`), its glibc library directory (`-B`), and its loader and library path (`-Wl,-dynamic-linker`, `-Wl,-rpath`). The C++ wrappers also add the libstdc++ headers unless the caller passes `-nostdinc++`, which libstdc++ does when it builds itself. The stage 3 glibc carries the kernel headers in its own include directory, so the compiler of stage 3 needs one system header directory, and while it builds its own libraries it finds the startup files of glibc through `LIBRARY_PATH`.

All packages of the distribution after stage 3, including the kernel, systemd and Python, are built with `stdenv`.

## 7. Reproducibility

Every stage runs in the sandbox with the fixed build environment of RFC 0001 section 9.5, and every source is fetched by digest. The stages MUST therefore build to the same store paths on any machine, and each stage SHOULD give the same contents, which `lattice build --check` and the comparison of backends (RFC 0001 section 9.7) test. A stage whose contents differ between two builds is a bug in the package set and blocks a release.

The first check of the stage 3 glibc found such a bug: its static libraries differed between two builds, because `ar` and `strip` write the time stamp and owner of each member. The stage 3 Binutils is configured with `--enable-deterministic-archives`, and the debug information is removed with `strip -D`, which writes those fields as zero. After that change the stage 3 glibc, Binutils, GCC, GNU Make, sed, m4, grep and xz each rebuilt with the same contents on one machine. The comparison between two machines is not done yet.

## 8. Rebuilding the seed

The package set will hold a derivation `seed-archive` that builds the parts of section 5.1 from source with the stage tools, as programs for `x86_64-linux-musl` linked statically, and writes the archive in the format of section 5.2. It is not written yet.

A seed is released as follows:

1. The first seed, seed 0, is assembled once outside PyrixOS, as section 5.1 describes. It is published so that the stages can be built, but it is trusted only through its digest.
2. Stages 1 to 3 are built from seed 0, and `seed-archive` gives seed 1.
3. Stages 1 to 3 are built again from seed 1, and `seed-archive` gives seed 2.
4. Seed 1 is published only if seed 1 and seed 2 are the same file.

When step 4 holds, the seed is a fixed point: the stage tools rebuild exactly the seed they came from. Because seed 1 was compiled by a GCC that PyrixOS built from source, seed 1 depends only on the sources and not on the compiler that built seed 0. Anyone can check this by building seed 0 with a different compiler, such as the one of another distribution, and repeating steps 2 and 3. Getting the published seed again is evidence that neither the seed nor the first compiler adds anything that the sources do not describe. This is the method of diverse double compiling described by David A. Wheeler.

A continuous integration job SHOULD repeat steps 2 and 3 from the published seed for every release of PyrixOS and fail when the result differs.

## 9. Measurement

The bootstrap reports, for each stage, the build time on the reference machine, the number of derivations, and the total size of its outputs. It also reports the size of the seed archive and of the unpacked seed. These numbers are published with each release so that a change that slows the bootstrap down or grows the seed is visible.

## 10. Security considerations

The seed is the one binary that PyrixOS runs without building it. Its digest is written in a reviewed PyBonsai file, a different archive fails `fetch_url`, and section 8 makes its contents checkable by anyone with another compiler.

`builtin:unpack` runs with the rights of the Lattice daemon. The checks of section 5.3 MUST apply to every archive, not only to the seed, and the output goes into the staging directory and is published to the store atomically like any other output, so a failed unpack leaves nothing behind.

A stage that could reach the host would make the bootstrap depend on it. The sandbox already holds no host paths and has no network (RFC 0001 section 9), and the reference check of section 6 makes sure that no output after stage 3 keeps a path to a tool that was not built from source.

## 11. Alternatives considered

Taking the compiler from the host
:   Rejected. The build would depend on the host, and the sandbox has no host paths by design.

Bootstrap tools built by another distribution
:   Nix and Guix both started from binaries made by an earlier build of themselves. PyrixOS follows the same idea but adds the fixed point check of section 8, so the published seed is not taken on trust from its first build.

Full-source bootstrap
:   The live-bootstrap and stage0 projects, and the reduced binary seed of GNU Mes used by Guix, build a C compiler from a seed of a few hundred bytes of machine code. This removes the binary seed almost entirely, but adds several hundred steps and a long build time, and needs a kernel or a simple machine to run the first steps. It is the goal for a release after 1.0. The stages of section 6 do not change when it comes; only stage 0 is replaced.

A seed linked against glibc
:   Rejected. Static linking against musl keeps the seed small and makes it work at any store path, with no loader path to rewrite.

## 12. Resolved and deferred questions

Architectures
:   PyrixOS 1.0 is built for x86_64 only. Each further architecture gets its own seed, built and checked in the same way.

Full-source bootstrap
:   Deferred past 1.0, as described in section 11.

Seed updates
:   A new seed is released only when a stage 1 package needs it, and the release follows section 8. Updating a package of stage 2 or 3 does not need a new seed.
