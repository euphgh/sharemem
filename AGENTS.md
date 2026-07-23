# ShareMemory Repository Guidance

This file applies to the whole repository. Keep it as a short navigation page;
put design contracts in `docs/` and detailed API contracts in source comments.

Before changing code, read:

1. [docs/index.md](docs/index.md) for the repository and verification overview.
2. [docs/mem-vlm-interface-spec.md](docs/mem-vlm-interface-spec.md) for MEM/VLM
   interface behavior.
3. [docs/vlm-reservation-verification-architecture.md](docs/vlm-reservation-verification-architecture.md)
   for the reservation-agent architecture.
4. [docs/systemverilog-code-style.md](docs/systemverilog-code-style.md) before
   writing SystemVerilog/UVM classes.
5. The existing code in `ver_common/` and `ut_shm/` that is closest to the
   requested change.

Follow the user-approved development stage. For the current
`vlm_reservation_agent` API-shape stage, add declarations and documentation
only; do not implement behavior until explicitly requested.

Preserve unrelated user changes. After source changes, run a syntax-oriented
check that covers the changed files, and keep generated artifacts outside
source and documentation directories.
