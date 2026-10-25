---
title: Lattice Package Manager
description: >-
  Lattice evaluates PyBonsai descriptions into derivations, builds them in a
  namespace sandbox, publishes them to an immutable store and collects
  garbage.
---

# Lattice package manager

<div class="pyrix-meta" markdown>
<span class="pyrix-flag">Draft</span>
<span>Defined in <strong>RFC 0001 §6, §8, §14, §15</strong></span>
<span>Implementation <strong>Pure Python</strong></span>
</div>

Lattice is the package manager at the centre of PyrixOS. It takes a PyBonsai description and carries it all the way to installed software. It evaluates the description, turns it into derivations, builds each derivation in a sandbox, publishes the results to the store, and later removes what is no longer needed. Lattice is written in Python and depends only on the Python standard library, PyBonsai, [Pydantic](https://docs.pydantic.dev/) for its data models, and the Linux kernel. It needs no container runtime or external build tool. Its daemon is optional and lets several users share one store.

## From description to store

```mermaid
---
config:
  themeVariables:
    fontSize: 16px
  flowchart:
    useMaxWidth: false
  sequence:
    useMaxWidth: false
---
flowchart TB
    a["PyBonsai file"] -->|"parse and interpret"| b["Derivation graph"]
    b -->|"already in store?"| c{"Hash known"}
    c -->|"yes"| e["Reuse store path"]
    c -->|"no"| d["Build in sandbox"]
    d --> f["Publish to store"]
    f --> g["Record references"]
```

Lattice works in stages and each one only consumes the output of the stage before it. The evaluator never builds, the sandbox never evaluates, and the store never runs build code. Because every derivation is identified by a hash of all its inputs, Lattice can see that a build has already been done and reuse its result without running it again.

## Derivations

A derivation is the exact recipe for one build. It names the package, the builder program and its arguments, the environment the builder sees, and the outputs it must produce. Any input that is itself a derivation, such as a source archive or a compiler, is part of the environment.

Lattice serialises each derivation to canonical JSON, with sorted keys, fixed encoding, and every input derivation replaced by its own hash. It then takes the SHA-256 digest of the result. That digest names the store path the build will produce. Changing anything that goes into a build, directly or several dependencies away, therefore produces a different hash and a different path, while identical recipes on different machines produce the same one.

## Standard library

The standard library is the only way a description reaches anything outside itself, and every function in it is pure.

| Function | Purpose |
| --- | --- |
| `derivation` | Creates a derivation from a name, builder, arguments, environment and outputs. |
| `fetch_url` | Declares a source by URL and expected SHA-256. The download happens at build time, outside the sandbox, and fails if the hash does not match. |
| `len`, `range`, `sorted`, `min`, `max`, `str`, `int` | Pure helpers for working with immutable values. |

New functions are added only through an RFC.

## Using Lattice from Python

Lattice is a Python library first, and the `lattice` command is a thin wrapper around it. Another program, such as a provisioning tool or a test harness, can do everything the command does by creating a `Lattice` object and calling its methods.

```python
from lattice import Lattice, Settings

lattice = Lattice(Settings(sandbox_backend="namespaces"), on_event=print)
result = lattice.evaluate("hello.pyb")
for name, drv in result.derivations.items():
    print(name, drv.store_path)
```

The library reads no settings from the machine unless asked, keeps no state between calls, returns immutable Pydantic data models, raises subclasses of `LatticeError`, reports progress through the optional `on_event` callable and the `lattice` logger, and ships type hints.

## Daemon and remote API

`lattice daemon` runs as the `lattice` user and is then the only process that writes to the store. Other processes reach it through `lattice.Client`, which has the same methods, results and errors as `Lattice`.

```python
from lattice import Client

local = Client()  # unix:///run/lattice/daemon.sock
remote = Client("https://builder.example:7420", ca_file="ca.pem",
                cert_file="me.pem", key_file="me.key")
```

| Transport | Caller identified by | Roles |
| --- | --- | --- |
| Unix socket `/run/lattice/daemon.sock` | Kernel peer credentials | Admin for root, the daemon user and `lattice-admins`; user for `lattice-users` |
| TLS 1.3 on a configured port | Client certificate or bearer token | As granted in the daemon settings |

Tools in other languages use the same interface directly, as JSON-RPC 2.0 at `POST /v1/rpc` or as REST at `POST /v1/<method>`, with the same JSON data models. Users may evaluate, build, check and switch their own `per-user/<name>` profiles, and admins may also collect garbage, push to caches and switch any profile. The daemon never opens a file named by a caller and always builds with its own settings. RFC 0001 sections 6.1 and 6.2 define the library, the daemon and the remote API.

## Measurement

Lattice times its own work so that the cost of each stage is visible. It records parse and evaluation time with the number of syntax tree nodes visited, sandbox setup and teardown time for every build, and the time taken and paths visited by each phase of garbage collection. Samples are held in memory and written out after the operation finishes, so timing never adds I/O to the work being timed. The metrics are listed in [RFC 0001 §15](../rfc/0001-pyrixos-architecture.md#15-measurement).
