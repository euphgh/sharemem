# ShareMemory Repository Guidance

This file applies to the whole repository. Keep it as a short navigation page;
put design contracts in `docs/` and detailed API contracts in source comments.

Before changing code, read:

1. [docs/index.md](docs/index.md) for the repository and verification overview.
2. [docs/ut_shm/index.md](docs/ut_shm/index.md) and the relevant linked area
   index for ut_shm work. DUT behavior is defined by the current documents in
   [docs/ut_shm/spec/](docs/ut_shm/spec/index.md).
3. [docs-old/documentation-migration-baseline.md](docs-old/documentation-migration-baseline.md)
   for source precedence in areas whose detailed documents are still pending.
4. For reservation-agent implementation details during the migration, consult
   the historical
   [reservation architecture](docs-old/vlm-reservation-verification-architecture.md),
   then verify it against the current MEM/VLM spec and source.
5. The temporary historical
   [SystemVerilog/UVM style guide](docs-old/systemverilog-code-style.md) before
   writing SystemVerilog/UVM classes.
6. The existing code in `ver_common/` and `ut_shm/` that is closest to the
   requested change.

Documents marked as pending are navigation entries, not current design
contracts. Current documents in `docs/ut_shm/spec/` supersede historical DUT
descriptions. In all other conflicts, current source and user-confirmed behavior
take precedence over historical text in `docs-old/`.

Preserve unrelated user changes. After source changes, run a syntax-oriented
check that covers the changed files, and keep generated artifacts outside
source and documentation directories.
