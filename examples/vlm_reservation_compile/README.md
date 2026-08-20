# VLM reservation agent compile example

This example checks that VCS can elaborate `RpuShmTop` together with:

- unified `vlm_agent`, including atomic monitoring, reservation checking, gid resolution,
  scheduling, MEM publication, and read response;
- unified `vlm_interface`;
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
all address bits from the reservation. No read/write beat alignment policy is
applied because the downstream SRAM accepts unaligned 32-byte accesses.

Run the external busy plusarg regression with:

```sh
scripts/ubuntu/check_vlm_reservation_vcs.sh external-busy
```

This passes `+EXTERNAL_BUSY_PERCENT=100`, confirms that it overrides the test
config value, and checks that both interface busy tables are driven high.

Run the dual-gid ownership and MEM resolver contract test with:

```sh
scripts/ubuntu/check_vlm_reservation_vcs.sh gid-contract
```

This test checks structured admission/match outcomes for target-gid and
other-gid external busy, same-bank/due write-port conflict, normal gid
resolution, unexpected MEM, and address mismatch. Expected negative reports
are matched by ID and exact count. The outcomes are diagnostic and coverage
metadata only; they do not control request admission or RTL outputs.

Run the deterministic external-busy policy test with:

```sh
scripts/ubuntu/check_vlm_reservation_vcs.sh directed-busy
```

The policy test covers exact drive cycles, inclusive cycle ranges, scheduler
window movement, precedence over percentage generation, and exclusion of
SHM-owned slots.

Run the unmatched MEM publication test with:

```sh
scripts/ubuntu/check_vlm_reservation_vcs.sh agent-metadata
```

This test checks config-to-scheduler policy propagation and confirms that an
unmatched published MEM transaction keeps `gid_valid==0` and
`reservation_matched==0`.

Run the positive-window MEM read snapshot test with:

```sh
scripts/ubuntu/check_vlm_reservation_vcs.sh read-snapshot
```

The target runs the same component harness with `FFD_CYC=1` and `FFD_CYC=2`.
It checks cutoff visibility, writes after the cutoff, partial strobes, repeated
writes, consecutive same-bank reads, gid isolation, exact response cycles, and
pending-read retirement. `FFD_CYC=0` is intentionally outside the current
implementation boundary.

Run all component targets with:

```sh
scripts/ubuntu/check_vlm_reservation_vcs.sh all
```
