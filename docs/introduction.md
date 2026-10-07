---
title: Introduction
description: >-
  PyrixOS is a reproducible, declarative Linux distribution configured in
  PyBonsai, a hermetic subset of Python, and built by the Lattice package
  manager.
---

# Introduction to PyrixOS

<div class="pyrix-meta" markdown>
<span class="pyrix-flag">Design stage</span>
<span>Specification <strong>RFC 0001</strong></span>
<span>Language <strong>Python syntax</strong></span>
</div>

PyrixOS is a Linux distribution in which the whole system is described in code and built reproducibly. A package, a set of packages, or a complete machine is written as a short description in PyBonsai, a restricted form of Python. The Lattice package manager turns that description into exact build recipes, builds each one in isolation, and keeps the results in a store where nothing is ever changed in place.

The same description always produces the same system. Installing, upgrading and removing software means producing a new description and building it, while earlier builds stay in the store until nothing refers to them any more. Rolling back is a matter of pointing at an earlier result.

<div class="pyrix-kv" markdown>
<div><div class="k">Configuration</div><div class="v">PyBonsai</div><div class="n">Python syntax, no side effects</div></div>
<div><div class="k">Evaluation</div><div class="v">Hermetic</div><div class="n">Always terminates, always repeatable</div></div>
<div><div class="k">Builds</div><div class="v">Namespace sandbox</div><div class="n">No network, no host filesystem</div></div>
<div><div class="k">Results</div><div class="v">Immutable store</div><div class="n">Named by a hash of every input</div></div>
<div><div class="k">Cleanup</div><div class="v">Garbage collector</div><div class="n">Removes only what nothing needs</div></div>
</div>

## Why Python

Declarative distributions already exist. NixOS and Guix System build an entire operating system from a description and give the same guarantees PyrixOS aims for. Both ask the user to learn a dedicated language first, a lazy functional language in the case of Nix and Scheme in the case of Guix.

PyrixOS takes the same approach and changes the language. Many system administrators and developers already read and write Python, so PyBonsai keeps its syntax, its literals and its operators. What it removes are the parts of Python that make a result depend on something other than the description, such as imports, file and network access, mutation and loops that may never end. A PyBonsai file is never run as a Python program. Lattice reads its syntax tree and interprets only what the language allows.

## How the pieces fit

```mermaid
flowchart TB
    subgraph eval ["Evaluate"]
        pyb["PyBonsai description"] --> ev["Hermetic evaluator"]
        ev --> drv["Derivations"]
    end
    subgraph build ["Build"]
        drv --> sb["Namespace sandbox"]
    end
    subgraph keep ["Keep"]
        sb --> st["Immutable store"]
        st --> db[("Dependency graph")]
        db --> gc["Garbage collector"]
    end
```

| Component | What it does |
| --- | --- |
| [PyBonsai](components/pybonsai.md) | The configuration language. Python syntax with a fixed allow list of constructs, single assignment and immutable values. |
| [Lattice package manager](components/lattice.md) | Evaluates PyBonsai, produces derivations identified by a SHA-256 hash, and drives builds, the store and collection. |
| [Build sandbox](components/sandbox.md) | Runs each build in fresh Linux user, mount, network and PID namespaces with no network access and only its inputs visible. |
| [Immutable store and garbage collector](components/store.md) | Publishes build outputs atomically as read-only paths, tracks their dependencies in SQLite, and removes paths no root can reach. |

## Project status

PyrixOS is at the design stage and there is nothing to install yet. The architecture is set out in [RFC 0001](rfc/0001-pyrixos-architecture.md), which is open for comment, and the [roadmap](roadmap.md) shows the order in which the components will be built once it is accepted.
