# SHMINS sequence empty-design compile

This example compiles the split SHMINS sequence-item hierarchy and
`shmins_mst_unit_sequence` in a minimal UVM package without a DUT. It checks
SystemVerilog syntax, constraint inheritance, UVM factory registration, and
queue-based allowed-value constraints. It does not run randomization or prove
DUT behavior.

Run it on the configured remote EDA server from the repository root:

```sh
scripts/ubuntu/check_shmins_sequence_vcs.sh compile
```

Generated VCS outputs remain under `examples/shmins_sequence_compile/build/`.

