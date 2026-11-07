# Ryoku Adaptive Desktop Foundation (Mission 016) — CLOSEOUT

**Merge:** não. Tip validado (manual NixOS): **`572f77db8838cdbcbd9717abe9d3f82b9fecfc61`**.

CI ≠ guest. Never invent `PASS_MANUAL` from host unit tests or package CI.

## Claims oficiais (≠ CI)

| Item | Status |
|------|--------|
| **`ADAPTIVE_PROFILE_SWITCH`** | **`PASS_MANUAL`** — F1/F2/F3 trocam perfis |
| **`KEYBOARD_ARROWS_TAB`** | **`PASS_MANUAL`** — setas / Tab OK no shell gráfico |
| **`LITE_USABILITY`** | **`POSITIVE_MANUAL_FEEDBACK`** — Lite fluido |
| **`BALANCED_USABILITY`** | **`POSITIVE_MANUAL_FEEDBACK`** — Balanced equilibrado |
| **`ULTRA_PERCEIVED_SLOWDOWN`** | **`REPORTED_UNMEASURED`** — Ultra mais pesado mas utilizável (sem benchmark) |
| **`PERFORMANCE_BENCHMARK`** | **`NOT_RUN`** |

Sem declarar blur / transparência / 3D / compositor / Wayland completo.  
**Ultra → Balanced** paint/render fallback documentado (arch only).

## Profiles (Rust)

| Profile | Theme / layout | Animation | Render |
|---------|----------------|-----------|--------|
| **Lite** | Flat wallpaper; denser honesty | `ANIM NONE` | ~20 FPS; dirty rows only |
| **Balanced** | Gradient + hint card (015 look) | policy simple (no fake fade) | ~30 FPS; dirty rows |
| **Ultra** | Architecture only — **paint falls back to Balanced** | `ANIM ARCH ONLY` | same as Balanced |

## Session switch

- Env default: `RYOKU_DESKTOP_PROFILE=lite|balanced|ultra`
- Keyboard: **F1**=Lite, **F2**=Balanced, **F3**=Ultra
- Preserves Launcher / mouse / serial / no continuous redraw / no visible fb clear

## Next

Mission **016.1** — Adaptive Performance (instrumentação; TCG ≠ hardware).

## Related

- Closeout 015.2.1: [`ryoku-shell-launcher-0152-1.md`](ryoku-shell-launcher-0152-1.md)
- Package: [`tests/qemu/README-ADAPTIVE.md`](../../tests/qemu/README-ADAPTIVE.md)
