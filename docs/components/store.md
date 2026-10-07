---
title: Immutable Store & Garbage Collector
description: >-
  PyrixOS keeps every build result as a read-only path named by a hash of its
  inputs, tracks dependencies in SQLite, and removes paths no root can reach.
---

# Immutable store and garbage collector

<div class="pyrix-meta" markdown>
<span class="pyrix-flag">Draft</span>
<span>Defined in <strong>RFC 0001 §9, §10, §11</strong></span>
<span>Location <strong>/lattice/store</strong></span>
</div>

Everything Lattice builds is kept in the store, a single directory in which each entry is written once and never changed. Software is never upgraded in place. A new version is a new entry beside the old one, and the system switches from one to the other. Old entries stay until nothing needs them, and then the garbage collector removes them.

## Store paths

Each entry is a directory named `/lattice/store/<hash>-<name>`, for example `/lattice/store/3x9k…-hello-2.12.1`. The hash is the derivation hash, so it covers every input to the build. Two different builds can never claim the same path, and if a path already exists the build it represents has already been done.

## Publishing a build

```mermaid
flowchart LR
    out["Sandbox /out"] -->|"copy"| stage["Staging directory<br/>same filesystem as store"]
    stage -->|"atomic rename"| path["/lattice/store/hash-name"]
    path -->|"remove write bits"| ro["Read-only path"]
    ro -->|"one transaction"| db[("Register path<br/>and references")]
```

A rename is atomic only within one filesystem, and the sandbox output lives in memory. Lattice therefore first copies the output to a staging directory on the same filesystem as the store, then moves it into place with a single rename. Anyone looking at the store sees either no entry or a complete one, never a partial one. Lattice then removes write permission from every file and directory in the entry, so any later attempt to change it fails with a permission error.

## Tracking dependencies

An SQLite database records every store path, every run-time dependency between paths, and the roots that must be kept, such as the current system and anything a user has pinned. Run-time dependencies are found by scanning a new entry's files for the hashes of the paths it was built from. A program linked against a library contains that library's store path, and so the dependency is found without being declared.

| Table | Holds |
| --- | --- |
| `store_paths` | One row per entry, with its derivation hash, a hash of its contents and its size |
| `references` | One row per dependency, from the entry that needs it to the entry it needs |
| `gc_roots` | The named entries that must never be collected |

Because an entry can only depend on entries that existed before it was built, these dependencies form a directed acyclic graph.

## Garbage collection

The collector works in two phases. It first marks every entry reachable from any root by following dependencies through the graph, using a recursive query inside SQLite so the graph does not have to be loaded into memory. It then sweeps, deleting every entry that was not marked, starting from those that depend on others so that no remaining record ever points at a deleted entry.

Store entries are read-only, so the collector restores write permission on each one immediately before deleting it. It removes the files first and the database record second, so an interrupted collection can at worst leave an unregistered directory behind for the next run to remove. Collection holds an exclusive lock on the store, so it never runs at the same time as a build that has not yet registered its result.

The schema, locking rules and deletion order are specified in [RFC 0001 §9 to §11](../rfc/0001-pyrixos-architecture.md#9-immutable-store).
