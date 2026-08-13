# ShareMemory Repository Guidance

This file applies to the whole repository. Keep it as a short navigation page;
put design contracts in `docs/` and detailed API contracts in source comments.

Before changing code, read:

1. [docs/index.md](docs/index.md) for the repository and verification overview.
2. [docs/ut_shm/index.md](docs/ut_shm/index.md) and the relevant linked area
   index for ut_shm work. DUT behavior is defined by the current documents in
   [docs/ut_shm/spec/](docs/ut_shm/spec/index.md).
3. [docs/ut_shm/verification-status.md](docs/ut_shm/verification-status.md) for
   known implementation gaps and their acceptance evidence.
4. [docs/development/systemverilog-code-style.md](docs/development/systemverilog-code-style.md)
   before writing or modifying repository-owned SystemVerilog/UVM code.
5. The existing code in `ver_common/` and `ut_shm/` that is closest to the
   requested change.

Current documents in `docs/` supersede historical descriptions in `docs-old/`.
If current source, current documentation, and requested behavior disagree, stop
and resolve the contract instead of inferring a new DUT rule from legacy code.

Preserve unrelated user changes. After source changes, run a syntax-oriented
check that covers the changed files, and keep generated artifacts outside
source and documentation directories.

Place only tests that require the real design under `ut_shm/tests/`. Place
component tests that compile and run without the real design under `examples/`;
do not use an empty or stub design result as evidence of DUT behavior.
