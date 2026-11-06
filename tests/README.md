# Tests

| Area | Path | Role |
|------|------|------|
| Virtual Lab | [`qemu/`](qemu/) | QEMU harness assets (T0/T1) |
| Rust unit tests | `zaquion-core/*/src` | `cargo test --workspace` |

Harness code: `zaquion-core/ryoku-virtlab`. Strategy: [`docs/testing/qemu-strategy.md`](../docs/testing/qemu-strategy.md), [`docs/testing/virtual-lab.md`](../docs/testing/virtual-lab.md).

No VMs are required for default CI. T1 is SKIPPED when QEMU is absent.
