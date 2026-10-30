---
title: Using the components in other projects
description: >-
  PyBonsai, Cloche and Trellis are released on PyPI on their own. This page
  shows how to install them, which versions to depend on, and how PyBonsai
  and Cloche work together in a program that is not PyrixOS.
---

# Using the components in other projects

<div class="pyrix-meta" markdown>
<span class="pyrix-flag">Released</span>
<span>Packages <strong>pybonsai-lang, cloche, trellis-kconfig</strong></span>
<span>Python <strong>3.12 or later</strong></span>
</div>

PyrixOS is built from separate packages, and three of them know nothing of PyrixOS. Any Python program can use them, in the way Starlark is used outside Bazel.

| PyPI package | Import name | Version | What it gives a program |
| --- | --- | --- | --- |
| `pybonsai-lang` | `pybonsai` | 1.1 | Configuration files in Python syntax that cannot read files, the network, the clock or the environment, and always finish with the same result |
| `cloche` | `cloche` | 1.1 | Running a program in an unprivileged Linux sandbox that sees only the paths it is given, with no network, and with memory, CPU and process limits in a delegated cgroup |
| `trellis-kconfig` | `trellis` | 1.0 | A Kconfig-style option tree whose choices a SAT solver checks, with explanations of conflicts |
| `pyrixos-lattice` | `lattice` | 0.11 | The PyrixOS package manager; its interface may change until PyrixOS 1.0 |

## Install

```sh
pip install pybonsai-lang cloche
```

In a project's `pyproject.toml`, allow every release of the same major version:

```toml
[project]
dependencies = [
  "pybonsai-lang>=1.0,<2",
  "cloche>=1.0,<2",
]
```

Within a major version, the names in each package's `__all__`, the fields of its data models and the behaviour its README promises do not change in a way that breaks a caller. For PyBonsai, a file that evaluates under 1.0 gives the same values under every 1.x release. A name to be removed first gives a `DeprecationWarning` for at least one minor release.

PyBonsai runs on any operating system. Cloche needs Linux with unprivileged user namespaces; `cloche status` reports whether a machine has them and, if not, why. On Ubuntu 23.10 and later, AppArmor restricts them unless `kernel.apparmor_restrict_unprivileged_userns` is 0 or the program has an AppArmor profile that allows them.

## PyBonsai and Cloche together

A common use is a tool whose users describe jobs in a file, and which runs each job without trusting it. PyBonsai keeps the description from doing anything but describe, and Cloche keeps the job from touching anything it was not given.

The description, `jobs.pyb`, is ordinary Python syntax. Functions, comprehensions and string operations are allowed; imports, `while`, mutation and I/O are not.

```python
# A list of jobs, each a program and its arguments.
tools = ["/usr", "/lib", "/lib64"]

def shell(name, script):
    return {"name": name, "program": "/usr/bin/sh", "args": ["-c", script], "binds": tools}

jobs = [
    shell("greet", "echo hello > /build/out"),
    shell("count", "/usr/bin/seq " + str(3) + " > /build/out"),
]
```

The program evaluates the file, turns each job into a Cloche `Command`, and runs it:

```python
import sys
import tempfile

import cloche
import pybonsai


def load_jobs(path: str) -> list[cloche.Command]:
    names = pybonsai.evaluate_file(path)
    return [
        cloche.Command(
            name=job["name"],
            program=job["program"],
            args=job["args"],
            binds=tuple(cloche.Bind(source=p, destination=p) for p in job["binds"]),
            outputs={"out": "/build/out"},
        )
        for job in names["jobs"]
    ]


def main(path: str) -> int:
    try:
        commands = load_jobs(path)
    except pybonsai.PyBonsaiError as error:
        print(f"{path}: {error}", file=sys.stderr)
        return 2
    for command in commands:
        try:
            outcome = cloche.run(command, tempfile.mkdtemp(), cloche.Limits(timeout=60))
        except cloche.ClocheError as error:
            print(error, file=sys.stderr)
            return 1
        with open(outcome.outputs["out"]) as output:
            print(command.name, output.read().split())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
```

```console
$ python runner.py jobs.pyb
greet ['hello']
count ['1', '2', '3']
```

A file that steps outside the language is refused before anything runs, with its file and line:

```console
$ python runner.py bad.pyb
bad.pyb: Import is not permitted: imports bring in code outside the standard library (bad.pyb, line 1)
```

Inside the sandbox, `PATH` is set to `/path-not-set`, so a job names its programs by absolute path. Everything outside the binds, `/build`, `/proc` and a minimal `/dev` is absent, including `/etc`.

## Giving files your own functions

Without a host, a PyBonsai file sees only the pure built-in functions such as `len`, `range` and `sorted`. A program adds its own through a `Host`:

```python
from pybonsai import Builtin, evaluate_source, make_host

host = make_host(names={"double": Builtin("double", lambda x: 2 * x)}, types={})
assert evaluate_source("y = double(21)", host=host)["y"] == 42
```

A host function must not read files, the clock or anything else outside its arguments, or the result of a file would no longer depend on the file alone. Host types must be immutable and hashable, and list the attributes a file may read.

## Errors

| Package | Base class | Raised for |
| --- | --- | --- |
| PyBonsai | `PyBonsaiError` | `RejectedSyntax` for a construct outside the language, `EvaluationError` for a failure while evaluating, and `LimitExceeded` when a size, depth or step limit is reached |
| Cloche | `ClocheError` | `InvalidCommand` for a command that does not fit together, `SandboxUnavailable` when the machine cannot run the backend, and `RunFailed` when the program fails, with the last lines of its log |
| Trellis | `ConfigError` | `ParseError` and `RejectedConstruct` for a Kconfig file outside the subset, `TreeError` for a tree that breaks a rule, `InvalidValue` for a value an option cannot take, `ConflictError` for choices that conflict, with the choices and rules involved, and `SolverUnavailable` for a missing solver backend |

## More

Each package's README lists its whole interface: [PyBonsai](https://github.com/PacketFive/pybonsai), [Cloche](https://github.com/PacketFive/cloche) and [Trellis](https://github.com/PacketFive/trellis). The [PyBonsai](components/pybonsai.md), [Build Sandbox](components/sandbox.md) and [Trellis](components/trellis.md) pages explain how each works.
