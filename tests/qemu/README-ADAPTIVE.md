# Ryoku Minimal — adaptive desktop package (Mission 016) — CLOSEOUT

Independent ZIP stacked on Mission 015.2.1 (PR #11). Does **not** run QEMU in CI/agent.

Tip validado (manual): **`572f77d`**.

| Check | Status |
|-------|--------|
| Musl init + console + shell-preview + DRM/input | CI **PASS** (host) |
| **`ADAPTIVE_PROFILE_SWITCH`** | **`PASS_MANUAL`** |
| **`KEYBOARD_ARROWS_TAB`** | **`PASS_MANUAL`** |
| **`LITE_USABILITY` / `BALANCED_USABILITY`** | **`POSITIVE_MANUAL_FEEDBACK`** |
| **`ULTRA_PERCEIVED_SLOWDOWN`** | **`REPORTED_UNMEASURED`** |
| **`PERFORMANCE_BENCHMARK`** | **`NOT_RUN`** |
| Blur / 3D / Wayland compositor | **Not** claimed |
| Ultra paint | falls back to **Balanced** (arch only) |

## Manual (NixOS)

```bash
chmod +x run-ryoku-shell-qemu.sh
./run-ryoku-shell-qemu.sh
RYOKU_DESKTOP_PROFILE=balanced \
  RYOKU_SHELL_QEMU_EXECUTE=1 RYOKU_SHELL_QEMU_CONFIRM=RUN \
  ./run-ryoku-shell-qemu.sh
# F1 Lite / F2 Balanced / F3 Ultra (Ultra = arch fallback Balanced)
```

## Docs

- `docs/testing/ryoku-adaptive-016.md`
