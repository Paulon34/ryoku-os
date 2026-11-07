# Ryoku Adaptive Performance (Mission 016.1)

**Guest results:** **`GUEST_NOT_RUN`** until human confirm (never auto `PASS_MANUAL`).

Stacked on Mission **016** closeout (tip `572f77d` validated; docs tip `6a7e38b`).

## Goals

- Instrument **compose** vs **present** (blit±flush)
- Metrics: redraw count, approx latency, scratch mem; **selected vs effective** profile
- Host comparison helpers Lite vs Balanced (caller-supplied samples only — **no invented numbers**)
- Investigate Ultra perceived slowdown: paint falls back to **Balanced**; TCG ≠ hardware
- Cut unnecessary alloc / full-frame compose on cursor dirty (band compose)
- Optional perf overlay: `RYOKU_SHELL_PERF_OVERLAY=1` (**off by default**)

## Honesty

| Claim | Status |
|-------|--------|
| Blur / transparency / 3D / compositor / full Wayland | **Not** claimed |
| Guest adaptive / perf timings | **`GUEST_NOT_RUN`** |
| QEMU TCG timings as hardware | **Never** |
| Invented benchmark numbers | **Never** |

## Ultra investigation (code honesty)

Ultra **selected** → **effective Balanced** for paint/render. Perceived weight vs Lite is the Balanced gradient/card path under QEMU TCG; vs Balanced paint path should match. See `ultra_slowdown_investigation()` in `ryoku-shell-preview`.

## Manual (after ZIP)

```bash
chmod +x run-ryoku-shell-qemu.sh
./run-ryoku-shell-qemu.sh
RYOKU_DESKTOP_PROFILE=balanced \
  RYOKU_SHELL_QEMU_EXECUTE=1 RYOKU_SHELL_QEMU_CONFIRM=RUN \
  ./run-ryoku-shell-qemu.sh
# Optional overlay: RYOKU_SHELL_PERF_OVERLAY=1
# Serial metrics every ~5s: PERF LITE->LITE n=… c=…us p=…us mem=…KiB
```

## Related

- Closeout 016: [`ryoku-adaptive-016.md`](ryoku-adaptive-016.md)
- Package: [`tests/qemu/README-ADAPTIVE-PERF.md`](../../tests/qemu/README-ADAPTIVE-PERF.md)
- Perf goals doc: [`docs/performance/targets.md`](../performance/targets.md)
