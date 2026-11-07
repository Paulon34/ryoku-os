# Ryoku Shell Input (Mission 015.1) — PARTIAL CLOSEOUT

**Closeout:** 2026-11-07 · tip **`f5cc1c4be7d397f850a169c1921a8aeba2461107`** · PR #10  
**Official claims are manual only (≠ CI).** No invented full PASS.

## Status matrix (Paulo NixOS visual)

| Item | Status | Evidence |
|------|--------|----------|
| **`SHELL_RENDER`** | **`PASS_MANUAL`** | UI / panel / dock OK |
| **`DOCK_VISUAL_FEEDBACK`** | **`PASS_MANUAL`** | 3rd dock icon highlighted on click |
| **`GUEST_INPUT`** | **`PARTIAL_PASS_MANUAL`** | Click reached dock; UI stayed visible |
| **`LAUNCHER_OPEN`** | **`NOT_CONFIRMED`** | — |
| **`KEYBOARD_INTERACTION`** | **`NOT_CONFIRMED`** | — |
| **`CURSOR_MOVEMENT`** | **`NOT_CONFIRMED`** | — |
| Wayland / Bash / Hyprland / full Desktop | **Not** claimed | — |

## What this was

Guest-evdev interactive shell on fb0: event loop, dock hit-test, illustrative
launcher path. Shell stayed alive with serial. Partial manual only — launcher
open, keyboard, and cursor motion not confirmed.

## Next

Mission **015.2** — Interactive Launcher (ABS caps, fact-based input indicators,
full launcher panel).

## Related

- Package: [`tests/qemu/README-SHELL-INPUT.md`](../../tests/qemu/README-SHELL-INPUT.md)
- Closeout 015: [`ryoku-shell.md`](ryoku-shell.md) (`SHELL_PREVIEW=PASS_MANUAL`)
