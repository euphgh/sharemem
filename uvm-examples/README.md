# VCS UVM smoke test

This directory contains a minimal UVM 1.2 project used to confirm that the
installed VCS compiler can compile and run a UVM test.

Run the complete smoke test with:

```sh
make
```

Compilation and simulation artifacts are written under `build/`. A successful
run prints:

```text
UVM_INFO ... [VCS_UVM_SMOKE] UVM smoke test passed
```

Remove generated artifacts with:

```sh
make clean
```

