# Ryoku Adaptive Desktop Foundation (Mission 016)

**Guest results:** **`GUEST_NOT_RUN`** until human confirm (never auto `PASS_MANUAL`).

## Profiles (Rust)

| Profile | Theme / layout | Animation | Render |
|---------|----------------|-----------|--------|
| **Lite** | Flat wallpaper; denser honesty | `ANIM NONE` | ~20 FPS; dirty rows only |
| **Balanced** | Gradient + hint card (015 look) | policy simple (no fake fade) | ~30 FPS; dirty rows |
| **Ultra** | Architecture only — **paint falls back to Balanced** | `ANIM ARCH ONLY` | same as Balanced |

Never claimed: blur, transparency, 3D, compositor, full Wayland.

## Session switch

- Env default: `RYOKU_DESKTOP_PROFILE=lite|balanced|ultra`
- Keyboard: **F1**=Lite, **F2**=Balanced, **F3**=Ultra
- Preserves Launcher / mouse / serial / no continuous redraw / no visible fb clear

## Related

- Closeout 015.2.1: [`ryoku-shell-launcher-0152-1.md`](ryoku-shell-launcher-0152-1.md)
- Package: [`tests/qemu/README-ADAPTIVE.md`](../../tests/qemu/README-ADAPTIVE.md)
