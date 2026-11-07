# Mission 015.2.1 — Flicker / input stability (on PR #11)

**Manual tip tested:** `052c84c` · **`GRAPHICS_FLICKER=FAIL_MANUAL`** (≠ CI)  
Guest: fb **941×993** 32bpp stride **3764**; event0/event1 Keyboard, event2 PointerAbs.

## Fixes in this revision

| Area | Change |
|------|--------|
| Render | Removed visible mmap clear in `blit_rgb_to_fb`; scanline convert; dirty rows; no vblank claim |
| Rest | QEMU shell profile: `vt.global_cursor_default=0` (fbcon cursor hide only) |
| Efficiency | Redraw only on visual change; motion coalesce; `RYOKU_SHELL_TARGET_FPS`; metrics |
| Input | Keep **all** keyboards + one pointer; partial reads; BTN_LEFT/TOUCH; launcher open/close |
| Honesty | `EVENTS RECEIVED` ≠ functional click/nav; no auto `PASS_MANUAL` |

## Flicker taxonomy (do not conflate)

| Symptom | Likely cause |
|---------|----------------|
| Blink while idle | fbcon hardware cursor (mitigate: `vt.global_cursor_default=0`) |
| Flash on every mouse move | Visible fb clear before blit (fixed 015.2.1) |
| Horizontal tear / double image | Host GTK/display path — not claimed fixed here |
| Full-screen strobe | Wrong clear / wrong geometry — check stride×height |

DRM pageflip / true vsync = **future** (docs only; not claimed on fbdev).

## Opt-in diag

```bash
RYOKU_SHELL_INPUT_DIAG=1 RYOKU_SHELL_TARGET_FPS=30 \
  RYOKU_SHELL_QEMU_EXECUTE=1 RYOKU_SHELL_QEMU_CONFIRM=RUN ./run-ryoku-shell-qemu.sh
```

## Guest results until re-test

`LAUNCHER_GUEST` / functional mouse / keyboard / flicker = **NOT_RUN** (or prior FAIL_MANUAL) until Paulo confirms.
