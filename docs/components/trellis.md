---
title: Trellis
description: >-
  Trellis is the PyrixOS configuration system. Options are written in a subset
  of Kconfig, and a SAT solver resolves the user's choices, explains conflicts
  and proposes fixes.
---

# Trellis

<div class="pyrix-meta" markdown>
<span class="pyrix-flag">Draft</span>
<span>Defined in <strong>RFC 0003</strong></span>
<span>Files <strong>Kconfig, defconfig, config.pyb</strong></span>
<span>Command <strong>trellis, lattice config</strong></span>
</div>

A PyrixOS system has options that depend on one another. A driver needs a subsystem, one stack in a slot excludes another, and a service needs its packages. Trellis lets a user choose these options from a menu in the style of Linux `menuconfig`, and uses a SAT solver to make sure the choices fit together before anything is evaluated or built. When they do not, it says which choices and rules are in conflict and what would remove the conflict, instead of turning an option off without saying why.

## Three files

| File | Written by | Holds |
| --- | --- | --- |
| `Kconfig` | The maintainers of the option tree | The options, their types, prompts, help, dependencies and defaults, in a subset of the Linux Kconfig language |
| `defconfig` | Trellis, from the user's choices | Only what the user chose, in the Linux defconfig format. It is kept under version control. |
| `config.pyb` | Trellis | Every option with its resolved value, as a generated PyBonsai file. `trellis check` confirms it is current. |

## A short example

```
config NET
	bool "Networking support"
	default y

config WIFI
	tristate "Wireless LAN"
	depends on NET
	select CRYPTO

config CRYPTO
	tristate "Cryptographic API"
```

With a `modules` option also in the tree, `trellis set WIFI=m` records `CONFIG_WIFI=m` in the defconfig and writes `config.pyb` with `NET` on and both `WIFI` and `CRYPTO` as modules. Asking for `NET=n` afterwards is refused with the reason:

```console
$ trellis set NET=n
trellis: these choices and rules cannot all hold:
  you set NET=n
  you set WIFI=m
  WIFI depends on NET (Kconfig:5)
trellis: run trellis explain NAME VALUE to see the ways to allow a choice
```

`trellis explain NAME` says why an option has its value, and `trellis explain NAME VALUE` lists the smallest sets of choices to drop so that it can have another.

## What it guarantees

| Property | How |
| --- | --- |
| The same tree and choices give the same configuration | The choices are fixed first, then defaults in the order of the tree, then every remaining option is made as small as possible. No step depends on which solution a solver finds. |
| Every solver backend agrees | The built-in solver in pure Python is the reference. PicoSAT can be used instead, and the tests compare both with a brute-force check. |
| A tree cannot reach outside itself | Kconfig macros, `option env` and `source` of paths outside the tree are refused. |
| A conflict is never resolved silently | Selecting an option whose dependencies fail is a conflict, where Linux would only warn. |
| Nothing is half written | Both files are written atomically, and nothing is written when the choices conflict. |

## Consoles

`trellis menu` is a full-screen menu built on `curses` from the standard library. A change that conflicts is undone, and the menu shows the conflict with up to three fixes that a single key applies. `trellis old` asks one line at a time about options that are new since the last `config.pyb`, for terminals without `curses` and for scripts. The other commands, `olddefconfig`, `defconfig`, `savedefconfig`, `allyes`, `allno`, `check` and `export-dimacs`, take Linux's names where the meaning is the same.

In PyrixOS, `lattice config` runs the same command, so `lattice config menu` opens the menu.

## Using Trellis outside PyrixOS

Trellis is a separate package, [trellis-kconfig](https://github.com/PacketFive/trellis) (imported as `trellis`), that depends only on Pydantic and does not use the Lattice store. Any project with a Kconfig-style option tree can use it, from Python or with the `trellis` command.

```python
from trellis import Configurator

configurator = Configurator.load("Kconfig", "defconfig")
configurator.set("WIFI", "m")
print(configurator.resolve().values)
configurator.save("defconfig", "config.pyb")
```

The Kconfig subset, the encoding into clauses, the order of resolution and the file formats are specified in [RFC 0003](../rfc/0003-configuration-system.md).
