# SHMINS sequence empty-design component checks

This example compiles the split SHMINS sequence-item hierarchy and
`shmins_mst_unit_sequence` in a minimal UVM package without a DUT. It checks
SystemVerilog syntax, constraint inheritance, UVM factory registration, and
queue-based allowed-value constraints. A second target randomizes every
sequence-item topology and verifies copy/compare behavior, including generated
address state. Neither target proves DUT behavior.

Run it on the configured remote EDA server from the repository root:

```sh
scripts/ubuntu/check_shmins_sequence_vcs.sh compile
```

Run the transaction copy/compare component test with:

```sh
scripts/ubuntu/check_shmins_sequence_vcs.sh copy
```

Run both targets with:

```sh
scripts/ubuntu/check_shmins_sequence_vcs.sh all
```

Generated VCS outputs remain under `examples/shmins_sequence_compile/build/`.
