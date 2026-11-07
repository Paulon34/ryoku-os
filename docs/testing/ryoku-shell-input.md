# Ryoku Shell Input (Mission 015.1)

**Status:** experimental interactive shell on fb0 via **guest** `/dev/input/event*`  
**Official claims until manual:**  
`INPUT_GUEST=NOT_RUN` · `MOUSE_INTERACTION=NOT_RUN` · `KEYBOARD_INTERACTION=NOT_RUN`

## Scope

- Shell stays alive (event loop) while serial console also works (PID1 background spawn + reap).
- Mouse cursor, dock hit-test, hover/select, Launcher panel on first dock icon, Esc closes.
- Basic keyboard dock nav (arrows / Tab / Enter / Esc).
- QEMU `virtio-keyboard-pci` + `virtio-tablet-pci` (guest nodes only — **not** host `/dev/input`).
- Alpine `evdev.ko` + `virtio_input.ko` packed with DRM modules (never NixOS host modules).

## Explicitly not claimed

Bash shell, Hyprland, Wayland, full Desktop, arbitrary app exec, product input stack.

## Related

- Closeout 015: [`ryoku-shell.md`](ryoku-shell.md) (`SHELL_PREVIEW=PASS_MANUAL`)
- Package: [`tests/qemu/README-SHELL-INPUT.md`](../../tests/qemu/README-SHELL-INPUT.md)
