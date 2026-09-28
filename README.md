# Pyrix

Pyrix is a declarative Linux distribution in which the whole system is described in Python and built reproducibly. It has two parts. PyBonsai is a restricted, side-effect-free subset of Python used to write system and package descriptions. Lattice is the package manager that evaluates those descriptions, builds packages in isolation and keeps the results in an immutable store.

The aim is the reproducibility of a functional package manager without requiring users to learn a new language.

## Design

PyBonsai files are never executed. Lattice parses them into a Python abstract syntax tree and interprets only an approved set of constructs. Imports, `while` loops, file and network access, mutation and dunder attribute access are rejected, so evaluation always terminates and the same input always produces the same result. The output is a set of build recipes called derivations, each identified by a SHA-256 hash of its contents.

Builds run inside Linux user, mount, network and PID namespaces created directly from Python, without Docker, Podman or Bubblewrap. A build sees only its own working and output directories and has no network access.

Finished outputs are moved atomically into `/lattice/store/<hash>-<name>` and made read-only. An SQLite database records the dependencies between store paths, and the garbage collector removes any path that no active root can reach.

## Status

Pyrix is at an early stage and nothing can be installed yet. The [development plan](development-plan.md) lists each phase and the conditions for completing it.

## Contributing

AI-assisted contributions follow the [Linux Kernel AI Coding Assistants Policy](https://docs.kernel.org/process/coding-assistants.html). AI tools must not add `Signed-off-by:` or `Co-authored-by:` trailers. An AI-assisted commit carries an `Assisted-by: AGENT_NAME:MODEL_NAME` trailer giving the model family only, a `Reviewed-by:` trailer for the human reviewer and the submitter's own `Signed-off-by:`.
