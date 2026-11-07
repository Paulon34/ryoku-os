# Ryoku Minimal — shell input package (Mission 015.1) — PARTIAL CLOSEOUT

Tip **`f5cc1c4`** · PR #10. Manual ≠ CI.

| Check | Status |
|-------|--------|
| Musl init + console + shell-preview + DRM/input modules | CI **PASS** (host) |
| **`SHELL_RENDER`** | **`PASS_MANUAL`** |
| **`DOCK_VISUAL_FEEDBACK`** | **`PASS_MANUAL`** |
| **`GUEST_INPUT`** | **`PARTIAL_PASS_MANUAL`** |
| **`LAUNCHER_OPEN` / `KEYBOARD_INTERACTION` / `CURSOR_MOVEMENT`** | **`NOT_CONFIRMED`** |
| Wayland / Bash / Hyprland / app exec | **Not** claimed |

## Manual (NixOS)

```bash
chmod +x run-ryoku-shell-qemu.sh
./run-ryoku-shell-qemu.sh
RYOKU_SHELL_QEMU_EXECUTE=1 RYOKU_SHELL_QEMU_CONFIRM=RUN \
  ./run-ryoku-shell-qemu.sh
```

## Docs

- `docs/testing/ryoku-shell-input.md`
- Next: Mission 015.2 Interactive Launcher
