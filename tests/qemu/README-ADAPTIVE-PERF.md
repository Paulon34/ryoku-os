# Ryoku Minimal — adaptive performance package (Mission 016.1)

Independent ZIP stacked on Mission 016 (PR #12). Does **not** run QEMU in CI/agent.

| Check | Status |
|-------|--------|
| Musl init + console + shell-preview + DRM/input | CI **PASS** (host) |
| Guest adaptive / perf | **`GUEST_NOT_RUN`** until human |
| Blur / 3D / Wayland compositor | **Not** claimed |
| QEMU TCG = hardware | **No** — TCG ≠ hardware |
| Invented timings | **Never** |

## Manual (NixOS)

```bash
chmod +x run-ryoku-shell-qemu.sh
./run-ryoku-shell-qemu.sh
RYOKU_DESKTOP_PROFILE=lite \
  RYOKU_SHELL_QEMU_EXECUTE=1 RYOKU_SHELL_QEMU_CONFIRM=RUN \
  ./run-ryoku-shell-qemu.sh
# F1 Lite / F2 Balanced / F3 Ultra
# RYOKU_SHELL_PERF_OVERLAY=1  # optional, off by default
```

## Docs

- `docs/testing/ryoku-adaptive-0161.md`
- Closeout 016: `docs/testing/ryoku-adaptive-016.md`
