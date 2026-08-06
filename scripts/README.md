# ShareMemory scripts

Platform-specific entrypoints are grouped by the host that starts the script:

- `local/`: run on the macOS development host. These scripts perform Slang
  checks, synchronize the Ubuntu clone, execute an Ubuntu command, or upload
  the test environment to CentOS.
- `ubuntu/`: run inside the Ubuntu VCS environment after synchronization.
- files kept directly under `scripts/` are shared utilities or local inputs
  that are not executable platform workflows.

The repository-root `Makefile` is intentionally retained as the Ubuntu full
environment compile entry. It uses the repository design stub by default and
can use another design root through `RPU_DIR`.

The `shmins_sequence_item` randomization benchmark uses:

- `local/check_shmins_random_benchmark_slang.sh` for macOS syntax checks;
- `ubuntu/run_shmins_random_benchmark.sh` for VCS compilation and timing.

Its source, profiles, constraint-isolation modes, and result fields are
documented in `examples/shmins_random_benchmark/README.md`.

CentOS has no repository-owned execution scripts. It receives only `ut_shm/`
and `ver_common/` through `local/upload_centos.py` and uses its own build and
regression framework.
