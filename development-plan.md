# Development plan

Development happens in three phases, and each one is reviewed before the next begins.

| Phase | Scope | Components | Done when |
| --- | --- | --- | --- |
| 1. PyBonsai evaluator | Interpret a restricted Python AST and produce deterministic derivations | `pybonsai/evaluator.py`, `lattice/derivation.py`, `lattice/stdlib.py`, `tests/test_evaluator.py` | Arithmetic, assignment, calls and loops over finite iterables evaluate correctly. Imports, `while`, I/O, mutation, dunder access and unsupported nodes are rejected. Identical derivations hash identically. |
| 2. Build sandbox | Run builds in isolated Linux namespaces with no network access | `lattice/sys_namespaces.py`, `lattice/fs_mounts.py`, `lattice/builder.py`, `tests/test_sandbox.py` | Builds run in user, mount, network and PID namespaces. Network access and writes outside `/build` and `/out` fail. Outputs are checked and temporary state is removed. |
| 3. Store and garbage collector | Keep build outputs in an immutable content-addressed store tracked in SQLite | `lattice/store.py`, `lattice/db.py`, `lattice/gc.py`, `tests/test_store_and_gc.py` | Outputs move atomically into the store and become read-only. Writes to the store fail. Garbage collection keeps everything reachable from active roots and removes the rest. |

The evaluator, sandbox and garbage collector each report timing data. These are AST evaluation time, sandbox setup and teardown time, and dependency graph traversal time.
