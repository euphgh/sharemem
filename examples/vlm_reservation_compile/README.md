# VLM reservation agent compile example

This example checks that VCS can elaborate `RpuShmTop` together with:

- `vlm_reservation_agent`;
- `vlm_memory_slv_agent`, including its monitor, driver, and sequencer;
- `vlm_reservation_interface` and `vlm_memory_interface`;
- the shared `clk_if`.

The compile and directed-test commands run on the Ubuntu VCS environment. Run
them from the repository root.

Compile without running the generated simulation:

```sh
scripts/ubuntu/check_vlm_reservation_vcs.sh compile
```

VCS writes all generated files to `build/`. Remove them with:

```sh
scripts/ubuntu/check_vlm_reservation_vcs.sh clean
```

Run the directed alignment-ownership and exact-address regression with:

```sh
scripts/ubuntu/check_vlm_reservation_vcs.sh alignment
```

The regression checks that read reservations and both write ports accept and
preserve nonaligned addresses. It also checks that a due MEM request must match
all address bits from the reservation; alignment policy belongs outside the
reservation agent.

Run the external busy plusarg regression with:

```sh
scripts/ubuntu/check_vlm_reservation_vcs.sh external-busy
```

This passes `+EXTERNAL_BUSY_PERCENT=100`, confirms that it overrides the test
config value, and checks that both interface busy tables are driven high.
