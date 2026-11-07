# Ryoku Minimal — adaptive desktop package (Mission 016)

Independent ZIP stacked on Mission 015.2.1 (PR #11). Does **not** run QEMU in CI/agent.

| Check | Status |
|-------|--------|
| Musl init + console + shell-preview + DRM/input | CI **PASS** (host) |
| Guest adaptive / launcher / input | **`GUEST_NOT_RUN`** until human |
| Blur / 3D / Wayland compositor | **Not** claimed |

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
