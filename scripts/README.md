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

CentOS has no repository-owned execution scripts. It receives only `ut_shm/`
and `ver_common/` through `local/upload_centos.py` and uses its own build and
regression framework.
