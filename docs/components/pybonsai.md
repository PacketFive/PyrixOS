---
title: PyBonsai
description: >-
  PyBonsai is the PyrixOS configuration language, a hermetic subset of Python
  that is interpreted from its syntax tree and never executed.
---

# PyBonsai

<div class="pyrix-meta" markdown>
<span class="pyrix-flag">Draft</span>
<span>Defined in <strong>RFC 0001 §7</strong></span>
<span>Files <strong>.pyb</strong></span>
<span>Baseline <strong>Python 3.12</strong></span>
</div>

PyBonsai is the language every PyrixOS package and system is written in. It looks like Python and is parsed by Python's own parser against the Python 3.12 grammar, so editors, syntax highlighting and formatters work on it without change. It behaves differently in one respect that matters. A PyBonsai file is never executed. Lattice reads its syntax tree and interprets each node itself, accepting only the constructs listed in the RFC and rejecting the whole file if it finds anything else.

## What it guarantees

| Property | How it is achieved |
| --- | --- |
| Evaluating a file always finishes | There is no `while`, every loop and comprehension runs over a finite collection that has already been evaluated, and recursion is rejected. |
| The same file gives the same result | There are no imports, no file or network access, no clock and no randomness. Sets are always read in one fixed order. The only outside functions are the pure functions of the Lattice standard library. |
| Values never change | Each name is assigned once. Lists become tuples and dictionaries become read-only mappings when they are created. |
| No way into the interpreter | Python builtins are not in scope, and only attributes on a fixed allow list can be read, so names such as `__class__` are rejected. |
| Bounded cost | Limits on integer size, string and collection length, call depth, nesting depth and nodes evaluated are fixed by the Lattice release, so a file succeeds or fails the same way on every machine. |

## A short example

```python
def hello(tools):
    src = fetch_url(
        url="https://ftp.gnu.org/gnu/hello/hello-2.12.1.tar.gz",
        sha256="<expected SHA-256 of the archive>",
    )
    script = (
        "export PATH=$tools/bin && tar xf $src && cd hello-2.12.1"
        " && ./configure --prefix=$out && make install"
    )
    return derivation(
        name="hello-2.12.1",
        builder=f"{tools}/bin/sh",
        args=["-c", script],
        env={"src": src, "tools": tools},
        outputs=["out"],
    )
```

`tools` is a derivation that provides a shell and the usual build programs. A build sees only the store paths its derivation names, so the shell comes from `tools`. `fetch_url` does not download anything when this file is evaluated. It declares a source and the hash it must have, and Lattice fetches and checks it later, at build time. `derivation` returns a record describing the build. Assigning to `hello` a second time, adding `import os`, or writing `src.__class__` would each make Lattice reject the file before evaluating any of it.

## What it leaves out

Some familiar Python is missing on purpose. There are no classes, exceptions, `with` blocks, `async`, `match` statements or `:=` assignments. Each of these either introduces mutable state, depends on failure for control flow, or lets a name be rebound inside an expression. Functions are allowed and can be shared between descriptions, but a function cannot call itself.

Python's builtins are not available at all. That removes code execution (`eval`, `exec`, `compile`, `__import__`), reflection (`getattr`, `type`, `globals` and similar), I/O (`open`, `print`, `input`), and the non-deterministic `hash` and `id`. `str.format` and `%` formatting are also removed, because a replacement field such as `{0.__class__}` reads an attribute inside the string where it cannot be checked. f-strings remain, since Python parses them into syntax tree nodes the evaluator does check. With no import statement, no module is reachable, including `os`, `sys`, `subprocess`, `socket`, `time` and `random`.

The full list of permitted and rejected syntax tree nodes, and the reason for each rejection, is in [RFC 0001 §7](../rfc/0001-pyrixos-architecture.md#7-pybonsai-language).

## Using PyBonsai outside PyrixOS

PyBonsai is a separate package, [pybonsai-lang](https://github.com/PacketFive/pybonsai) (imported as `pybonsai`), with no runtime dependencies and no knowledge of packages or builds. Any Python program can use it as a configuration language, in the way Starlark is used outside Bazel. The program passes its own functions and value types through a `Host`, and a file sees only those and the pure built-in functions of the prelude.

```python
from pybonsai import Builtin, evaluate_source, make_host

host = make_host(names={"double": Builtin("double", lambda x: 2 * x)}, types={})
assert evaluate_source("y = double(21)", host=host)["y"] == 42
```

Lattice is one such program: its standard library, with `derivation` and `fetch_url`, is a `Host`. A host name may also hold a constant, such as a dict of options, which a file reads as a read-only mapping; Lattice gives a system description the options chosen with Trellis this way, as `config`. A host name may also hold a function defined by an earlier evaluation, which runs in the scope of its own file; Lattice evaluates the package set in layers this way.
