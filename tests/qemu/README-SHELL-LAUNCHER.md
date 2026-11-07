# Ryoku Minimal — shell launcher package (Mission 015.2 / 015.2.1) — CLOSEOUT

Tip **`6993807`** · PR #11. Manual ≠ CI.

| Check | Status |
|-------|--------|
| Musl init + console + shell-preview + DRM/input modules | CI **PASS** (host) |
| **`GRAPHICS_STABILITY`** | **`PASS_MANUAL`** |
| **`MOUSE_LAUNCHER_OPEN`** | **`PASS_MANUAL`** |
| **`LAUNCHER_RENDER`** | **`PASS_MANUAL`** |
| **`KEYBOARD_INTERACTION` / `LAUNCHER_CLOSE`** | **`NOT_CONFIRMED`** |
| Wayland / host input / net / disks / app exec | **Not** claimed |

## Manual (NixOS)

```bash
chmod +x run-ryoku-shell-qemu.sh
./run-ryoku-shell-qemu.sh
RYOKU_SHELL_QEMU_EXECUTE=1 RYOKU_SHELL_QEMU_CONFIRM=RUN \
  ./run-ryoku-shell-qemu.sh
```

## Docs

- `docs/testing/ryoku-shell-launcher-0152-1.md`
- Next: Mission 016 Adaptive Desktop Foundation
