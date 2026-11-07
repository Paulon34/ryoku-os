# Ryoku Minimal — shell launcher package (Mission 015.2 / 015.2.1)

Independent ZIP stacked on Mission 015.1. Does **not** run QEMU in CI/agent.

| Check | Status |
|-------|--------|
| Musl init + console + shell-preview + DRM/input modules | CI **PASS** (host) |
| Tip `052c84c` flicker | **`GRAPHICS_FLICKER=FAIL_MANUAL`** (manual; ≠ CI) |
| Guest launcher / input after 015.2.1 | **`NOT_RUN`** until re-test |
| Wayland / host input / net / disks / app exec | **Not** claimed |

See `docs/testing/ryoku-shell-launcher-0152-1.md`.

## Manual (NixOS)

```bash
chmod +x run-ryoku-shell-qemu.sh
./run-ryoku-shell-qemu.sh
RYOKU_SHELL_QEMU_EXECUTE=1 RYOKU_SHELL_QEMU_CONFIRM=RUN \
  ./run-ryoku-shell-qemu.sh
```

Expect: fact indicator (UNAVAILABLE/DETECTED/EVENTS RECEIVED); first dock icon opens
Ryoku Launcher; categories/focus/close; Esc closes; serial OK.

## Docs

- `docs/testing/ryoku-shell-launcher.md`
