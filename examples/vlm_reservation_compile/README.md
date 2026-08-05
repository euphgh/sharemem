# VLM reservation agent compile example

This example checks that VCS can elaborate `RpuShmTop` together with:

- `vlm_reservation_agent`;
- `vlm_memory_slv_agent`, including its monitor, driver, and sequencer;
- `vlm_reservation_interface` and `vlm_memory_interface`;
- the shared `clk_if`.

Compile without running the generated simulation:

```sh
make compile
```

VCS writes all generated files to `build/`. Remove them with:

```sh
make clean
```

Run the directed write-address alignment and exact-match regression with:

```sh
make alignment-test
```

The regression checks that write reservation port 0 accepts and preserves a
nonaligned address, write port 1 rejects one, and a due `mem_waddr` must match
all address bits from the reservation.
