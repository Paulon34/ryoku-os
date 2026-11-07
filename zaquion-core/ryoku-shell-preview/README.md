# `ryoku-shell-preview` — Mission 015 / 016 / 016.1 / **016.2**

Illustrative **desktop layout** + **Ryoku Launcher** on `/dev/fb0`. Adaptive
profiles Lite/Balanced/Ultra; performance instrumentation; opt-in controlled
benchmark.

Not a product Desktop. Not Wayland. No blur/3D. No Bash guest harness.

## Honesty

| Claim | Status |
|-------|--------|
| Software layout + launcher + present to fb0 | Host unit / package |
| Guest confirm / controlled benchmark | **`NOT_RUN`** until human |
| Auto `PASS_MANUAL` / invented timings from CI | **Never** |
| QEMU TCG = physical | **No** |

## Controlled benchmark (016.2)

- Off by default. `RYOKU_CONTROLLED_BENCHMARK=1` (or cmdline `ryoku.controlled_benchmark=1`)
- Identical 24 full + 24 band frames per profile; mean/p95; selected→effective
- Serial lines mark `COST_INSTRUMENTED=1 TCG_NE_HW=1`
- Metric windows reset on F1/F2/F3

## Build

```bash
cd zaquion-core
cargo test -p ryoku-shell-preview -p ryoku-init
cargo build -p ryoku-shell-preview --release --target x86_64-unknown-linux-musl
```
