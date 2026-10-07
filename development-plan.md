# Development plan

PyrixOS is designed before it is built. Each phase starts only when the one before it is complete, and implementation starts only when its RFC is accepted.

| Phase | Scope | Deliverables | Done when |
| --- | --- | --- | --- |
| 0. Architecture RFC | Agree the design of the language, the build sandbox, the store, the garbage collector, profiles and binary caches | RFC 0001 PyrixOS Architecture, published on the documentation site | The RFC has been reviewed in public, its open questions are resolved or deferred to named follow-up RFCs, and its status is Accepted. |
| 1. PyBonsai evaluator | Interpret a restricted Python syntax tree and produce deterministic derivations | Hermetic evaluator, derivation format, Lattice standard library, evaluator test suite | Permitted constructs evaluate correctly. Imports, `while`, I/O, mutation, recursion, dunder access and unsupported nodes are rejected. Identical derivations hash identically on different machines. |
| 2. Build sandbox | Run builds in isolated Linux namespaces with no network access | Namespace setup, sandbox filesystem, build runner, sandbox test suite | Builds run in user, mount, network and PID namespaces. Network access and writes outside `/build` and `/out` fail. Missing outputs fail the build and temporary state is removed. |
| 3. Store and garbage collector | Keep build outputs in an immutable store tracked in SQLite | Store publication, dependency database, garbage collector, store test suite | Outputs move atomically into the store and become read-only. Writes to the store fail. Collection keeps everything reachable from a root and removes the rest. |
| 4. Profiles and stacks | Select what is active through generations, with one active stack per slot | Profile generations, rollback, stack slots, activation with kernel module checks, activation test suite | Switching and rolling back are atomic. A slot never holds two stacks. Kernel modules change only while their devices are unused, and a stack in use by a running process is never collected. |
| 5. Binary caches | Fetch prebuilt store paths instead of building them | Cache format, signing, `lattice push`, HTTP substitution, CernVM-FS full copies and shallow paths, `lattice materialise`, cache test suite | Unsigned or altered paths are rejected. A path fetched from a cache is identical to one built locally. Shallow paths work as slots, kernel modules are always local, and collection removes only the symlink of a shallow path. |

Phases 1 to 5 each report timing for their main operation. These are evaluation time per syntax tree node, sandbox setup and teardown time, garbage collector traversal time, substitution time, and time to first open of a file in a shallow path.
