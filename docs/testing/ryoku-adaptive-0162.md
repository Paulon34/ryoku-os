# Ryoku Controlled Performance (Mission 016.2)

**Guest results:** **`CONTROLLED_BENCHMARK=NOT_RUN`** until human confirm (never auto `PASS_MANUAL`).

Stacked on Mission **016.1** closeout (tip `d2785f4` validated; docs tip `53bf7a0`).

## Controlled benchmark (opt-in)

Off in normal interactive use. Enable with:

- Guest env: `RYOKU_CONTROLLED_BENCHMARK=1`
- Or QEMU host (allowlisted cmdline): `RYOKU_CONTROLLED_BENCHMARK=1` → `ryoku.controlled_benchmark=1`

Identical workload **per profile** (Lite → Balanced → Ultra):

| Phase | Frames |
|-------|--------|
| Full-frame compose+present | 24 |
| Partial (band) compose+present | 24 |

Serial summary includes: selected→effective, full/band counts, mean/p95 compose/present/total, mean full vs band totals, scratch KiB, `COST_INSTRUMENTED=1`, `TCG_NE_HW=1`.

Metric windows reset on F1/F2/F3 profile switch (no mixed-profile windows).

## Allowlisted QEMU → guest params

| Host env | Cmdline token | Guest env |
|----------|---------------|-----------|
| `RYOKU_DESKTOP_PROFILE=lite\|balanced\|ultra` | `ryoku.profile=…` | `RYOKU_DESKTOP_PROFILE` |
| `RYOKU_SHELL_PERF_OVERLAY=1` | `ryoku.perf_overlay=1` | `RYOKU_SHELL_PERF_OVERLAY` |
| `RYOKU_CONTROLLED_BENCHMARK=1` | `ryoku.controlled_benchmark=1` | `RYOKU_CONTROLLED_BENCHMARK` |

Unknown `ryoku.*` keys are ignored. **T3** boot-seed append (`console=ttyS0` / earlyprintk) is unchanged — no `ryoku.*`.

## Instrumentation cost

`Instant` wrappers around compose/present add timer + bookkeeping overhead. Controlled lines mark `COST_INSTRUMENTED=1`. Do **not** treat deltas as pure paint cost. **QEMU TCG ≠ physical hardware.**

## Honesty

| Claim | Status |
|-------|--------|
| Blur / 3D / compositor / Wayland | **Not** claimed |
| Invented / favored numbers | **Never** |
| Guest controlled run | **`NOT_RUN`** until manual |
| TCG = physical | **No** |

## Manual

```bash
chmod +x run-ryoku-shell-qemu.sh
RYOKU_CONTROLLED_BENCHMARK=1 RYOKU_DESKTOP_PROFILE=balanced \
  RYOKU_SHELL_QEMU_EXECUTE=1 RYOKU_SHELL_QEMU_CONFIRM=RUN \
  ./run-ryoku-shell-qemu.sh
# Serial: CONTROLLED LITE->LITE … / BALANCED->BALANCED … / ULTRA->BALANCED …
```

## Related

- Closeout 016.1: [`ryoku-adaptive-0161.md`](ryoku-adaptive-0161.md)
- Package: [`tests/qemu/README-CONTROLLED-PERF.md`](../../tests/qemu/README-CONTROLLED-PERF.md)
