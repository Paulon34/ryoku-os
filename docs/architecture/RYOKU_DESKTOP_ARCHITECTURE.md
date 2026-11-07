# Ryoku Desktop Architecture (Missions 017–020)

**Status:** living design notes. Not a product compositor. Guest results stay
**`GUEST_NOT_RUN` / `NOT_RUN`** until manual confirmation. Never invent `PASS_MANUAL`.

## Stack overview

```
┌─────────────────────────────────────────────┐
│  Internal apps (018) — allowlist only       │
│  About / System Monitor / Settings / Files  │
├─────────────────────────────────────────────┤
│  Desktop input + lifecycle (019)            │
│  focus / drag / resize / dock / shortcuts   │
├─────────────────────────────────────────────┤
│  WindowManager (017) — in-process Rust      │
│  geometry · z-order · dirty · chrome        │
├─────────────────────────────────────────────┤
│  Display / input backends (020)             │
│  fbdev (default) · DRM/KMS study+fallback   │
│  Wayland: docs/arch only — not implemented  │
├─────────────────────────────────────────────┤
│  Adaptive Lite/Balanced/Ultra (016)         │
│  Ultra → Balanced paint (no blur/3D)        │
├─────────────────────────────────────────────┤
│  PID1 + serial console + T3 seed (008–015)  │
└─────────────────────────────────────────────┘
```

## Mission 017 — Window system

- `WindowManager` owns windows, focus, z-order, dirty rectangles
- Chrome: titlebar drag, edge resize, min/max/close
- **No** external process spawn; **no** Wayland claim
- Compose paints windows into the software RGB buffer; present uses existing
  dirty/scanline blit (no visible fb clear)

## Mission 018 — Internal apps

- Launcher categories map to **allowlisted** in-process apps
- About, System Monitor (illustrative), Settings (no persist), Files RO
- Ultra still falls back to Balanced for paint

## Mission 019 — Desktop input

- Pointer focus / drag / resize coordinated with dock + launcher
- Keyboard shortcuts must **not** conflict with F1–F3 profile switch
- Lifecycle: Created → Visible → Focused → Minimized → Closed

## Mission 020 — Graphics backend abstraction

- `DisplayBackendKind` / `DisplayBackendSelection` / `InputBackendKind` / `DamageRegion`
- Default: fbdev mmap path (014.2 / 015.2.1)
- DRM/KMS: study + selection stub — **always falls back to fbdev** in 020 (no modeset ioctls)
- Wayland: architecture notes only — **`WAYLAND=ARCH_ONLY`** (not a Wayland compositor)
- Env allowlist: `RYOKU_DISPLAY_BACKEND=fbdev|drm`

## Explicit non-goals

- Blur / transparency / 3D effects
- Arbitrary app exec / Bash guest harness
- Declaring a Wayland compositor or product Desktop
- Auto `PASS_MANUAL` from CI or host unit tests
- Merging QEMU TCG timings with physical hardware claims

## Related

- Adaptive: `docs/testing/ryoku-adaptive-016.md`
- Window: `docs/testing/ryoku-window-system-017.md`
- ROADMAP Fase 2.16+
