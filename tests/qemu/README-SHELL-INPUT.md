# Ryoku Minimal — shell input package (Mission 015.1)

Independent ZIP from Mission 015 closeout tip. Builds musl init+console+shell-preview
with DRM **and** guest input modules. Does **not** run QEMU in CI/agent.

| Check | Status |
|-------|--------|
| Musl init + console + `ryoku-shell-preview` + DRM/input modules | CI **PASS** (host) |
| **`INPUT_GUEST`** | **`NOT_RUN`** until human |
| **`MOUSE_INTERACTION`** | **`NOT_RUN`** until human |
| **`KEYBOARD_INTERACTION`** | **`NOT_RUN`** until human |
| Wayland / Bash / Hyprland / app exec | **Not** claimed |

## Manual (NixOS)

```bash
chmod +x run-ryoku-shell-qemu.sh
./run-ryoku-shell-qemu.sh
RYOKU_SHELL_QEMU_EXECUTE=1 RYOKU_SHELL_QEMU_CONFIRM=RUN \
  ./run-ryoku-shell-qemu.sh
```

Expect: panel/dock/cursor; click first dock icon → Launcher; Esc closes; serial still works.

## Docs

- `docs/testing/ryoku-shell-input.md`
