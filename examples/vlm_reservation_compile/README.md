# VLM reservation agent compile example

This example checks that VCS can elaborate `RpuShmTop` together with
`vlm_reservation_agent`, `vlm_reservation_interface`, `vlm_memory_interface`,
and the shared `clk_if`.

Compile without running the generated simulation:

```sh
make compile
```

VCS writes all generated files to `build/`. Remove them with:

```sh
make clean
```
