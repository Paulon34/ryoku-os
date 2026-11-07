# Ryoku Interactive Launcher (Mission 015.2)

**Status:** experimental Ryoku Launcher on fb0 (guest evdev)  
**Guest results:** **`NOT_RUN`** until human confirm (never auto `PASS_MANUAL`)

## Scope

- Launcher panel: title, categories, focus, close control, adaptive geometry
- Mouse: cursor / hover / select / open-close
- ABS axis ranges from device caps (`EVIOCGABS`) — not assumed 0–32767
- Device selection: ≤1 pointer + ≤1 keyboard; skip conflicting extras
- Keyboard: Tab / arrows / Enter / Esc
- Fact-based panel indicators only: `INPUT UNAVAILABLE` / `INPUT DETECTED` / `EVENTS RECEIVED`
- Low CPU event loop (sleep; no busy-loop)

## Explicitly not claimed

Wayland, host `/dev/input`, networking, disks, Bash/Hyprland, app exec, product Desktop.

## Related

- 015.1 partial: [`ryoku-shell-input.md`](ryoku-shell-input.md)
- Package: [`tests/qemu/README-SHELL-LAUNCHER.md`](../../tests/qemu/README-SHELL-LAUNCHER.md)
