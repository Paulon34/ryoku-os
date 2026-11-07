# Ryoku Minimal — adaptive performance package (Mission 016.1) — CLOSEOUT

Independent ZIP stacked on Mission 016 (PR #12). Does **not** run QEMU in CI/agent.

Tip validado (manual): **`d2785f4`**.

| Check | Status |
|-------|--------|
| Musl init + console + shell-preview + DRM/input | CI **PASS** (host) |
| **`ADAPTIVE_PERF_GUEST`** | **`PASS_MANUAL`** |
| **`PROFILE_SWITCH`** | **`PASS_MANUAL`** |
| **`PERF_METRICS`** | **`PASS_MANUAL`** |
| **`CONTROLLED_BENCHMARK`** | **`NOT_RUN`** |
| Blur / 3D / Wayland | **Not** claimed |
| “Lite slower” from mixed windows | **Not** concluded |
| QEMU TCG = hardware | **No** |

## Manual (NixOS)

```bash
chmod +x run-ryoku-shell-qemu.sh
./run-ryoku-shell-qemu.sh
RYOKU_DESKTOP_PROFILE=balanced \
  RYOKU_SHELL_QEMU_EXECUTE=1 RYOKU_SHELL_QEMU_CONFIRM=RUN \
  ./run-ryoku-shell-qemu.sh
# F1 Lite / F2 Balanced / F3 Ultra
# RYOKU_SHELL_PERF_OVERLAY=1  # optional, off by default
```

## Docs

- `docs/testing/ryoku-adaptive-0161.md`
- Closeout 016: `docs/testing/ryoku-adaptive-016.md`
