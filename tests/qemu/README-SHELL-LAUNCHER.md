# Ryoku Minimal — shell launcher package (Mission 015.2)

Independent ZIP stacked on Mission 015.1. Does **not** run QEMU in CI/agent.

| Check | Status |
|-------|--------|
| Musl init + console + shell-preview + DRM/input modules | CI **PASS** (host) |
| Guest launcher / input facts | **`NOT_RUN`** until human |
| Wayland / host input / net / disks / app exec | **Not** claimed |

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
