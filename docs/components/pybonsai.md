---
title: PyBonsai
description: >-
  PyBonsai is the PyrixOS configuration language, a hermetic subset of Python
  that is interpreted from its syntax tree and never executed.
---

# PyBonsai

<div class="pyrix-meta" markdown>
<span class="pyrix-flag">Draft</span>
<span>Defined in <strong>RFC 0001 §6</strong></span>
<span>Files <strong>.pyb</strong></span>
<span>Baseline <strong>Python 3.12</strong></span>
</div>

PyBonsai is the language every PyrixOS package and system is written in. It looks like Python and is parsed by Python's own parser against the Python 3.12 grammar, so editors, syntax highlighting and formatters work on it without change. It behaves differently in one respect that matters. A PyBonsai file is never executed. Lattice reads its syntax tree and interprets each node itself, accepting only the constructs listed in the RFC and rejecting the whole file if it finds anything else.

## What it guarantees

| Property | How it is achieved |
| --- | --- |
| Evaluation always terminates | There is no `while`, every loop and comprehension runs over a finite collection that has already been evaluated, and recursion is rejected. |
| The same file gives the same result | There are no imports, no file or network access, no clock and no randomness. The only outside functions are the pure functions of the Lattice standard library. |
| Values never change | Each name is assigned once. Lists become tuples and dictionaries become read-only mappings when they are created. |
| No way into the interpreter | Python builtins are not in scope, and only attributes on a fixed allow list can be read, so names such as `__class__` are rejected. |
| Bounded cost | Limits on integer size, string and collection length, call depth and nodes evaluated are fixed by the Lattice release, so a file succeeds or fails the same way on every machine. |

## A short example

```python
src = fetch_url(
    url="https://ftp.gnu.org/gnu/hello/hello-2.12.1.tar.gz",
    sha256="<expected SHA-256 of the archive>",
)

hello = derivation(
    name="hello-2.12.1",
    builder="/bin/sh",
    args=["-c", "tar xf $src && cd hello-2.12.1 && ./configure --prefix=$out && make install"],
    env={"src": src},
    outputs=["out"],
)
```

`fetch_url` does not download anything when this file is evaluated. It declares a source and the hash it must have, and Lattice fetches and checks it later, at build time. `derivation` returns a record describing the build. Assigning to `hello` a second time, adding `import os`, or writing `src.__class__` would each make Lattice reject the file before evaluating any of it.

## What it leaves out

Some familiar Python is missing on purpose. There are no classes, exceptions, `with` blocks, `async`, `match` statements or `:=` assignments. Each of these either introduces mutable state, depends on failure for control flow, or lets a name be rebound inside an expression. Functions are allowed and can be shared between descriptions, but a function cannot call itself.

Python's builtins are not available at all. That removes code execution (`eval`, `exec`, `compile`, `__import__`), reflection (`getattr`, `type`, `globals` and similar), I/O (`open`, `print`, `input`), and the non-deterministic `hash` and `id`. `str.format` and `%` formatting are also removed, because a replacement field such as `{0.__class__}` reads an attribute inside the string where it cannot be checked. f-strings remain, since Python parses them into syntax tree nodes the evaluator does check. With no import statement, no module is reachable, including `os`, `sys`, `subprocess`, `socket`, `time` and `random`.

The full list of permitted and rejected syntax tree nodes, and the reason for each rejection, is in [RFC 0001 §6](../rfc/0001-pyrixos-architecture.md#6-pybonsai-language).
