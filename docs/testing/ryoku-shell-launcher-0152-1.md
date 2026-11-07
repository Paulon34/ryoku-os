# Mission 015.2.1 — CLOSEOUT (PR #11)

**Closeout tip:** **`6993807ee0e1c37309b6274e19120fce7760d4a6`** · PR #11  
**Official claims are manual only (≠ CI).** No invented keyboard/close/general compat PASS.

## Status matrix (Paulo NixOS visual)

| Item | Status | Evidence |
|------|--------|----------|
| **`GRAPHICS_STABILITY`** | **`PASS_MANUAL`** | Flicker gone; shell OK; serial OK |
| **`MOUSE_LAUNCHER_OPEN`** | **`PASS_MANUAL`** | dock0 opened RYOKU LAUNCHER |
| **`LAUNCHER_RENDER`** | **`PASS_MANUAL`** | SYSTEM / DEV TOOLS / FILES / SETTINGS visible |
| **`KEYBOARD_INTERACTION`** | **`NOT_CONFIRMED`** | — |
| **`LAUNCHER_CLOSE`** | **`NOT_CONFIRMED`** | — |
| Wayland / full Desktop / compositor | **Not** claimed | — |

Guest: fb **941×474** 32bpp; mouse/input; `EVENTS RECEIVED` observed (fact only ≠ kbd/close PASS).

## Prior FAIL history (preserved)

Tip `052c84c`: **`GRAPHICS_FLICKER=FAIL_MANUAL`** (flicker on move + rest; launcher not opening).

## What 015.2.1 fixed (code)

| Area | Change |
|------|--------|
| Render | No visible mmap clear; scanline/dirty blit; no vblank claim |
| Rest | QEMU shell: `vt.global_cursor_default=0` (fbcon only) |
| Efficiency | Visual-change redraw; motion coalesce; FPS/metrics |
| Input | All keyboards + one pointer; partial reads |

## Next

Mission **016** — Adaptive Desktop Foundation (Lite / Balanced / Ultra profiles).

## Related

- Package: [`tests/qemu/README-SHELL-LAUNCHER.md`](../../tests/qemu/README-SHELL-LAUNCHER.md)
