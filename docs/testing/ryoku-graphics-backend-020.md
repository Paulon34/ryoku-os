# Ryoku Graphics Backend (Mission 020)

**Guest results:** **`GUEST_NOT_RUN`** until human. Never auto `PASS_MANUAL`.

## Backends

| Kind | Runtime |
|------|---------|
| **fbdev** (default) | Active present path (014.2 / 015.2.1) |
| **DRM/KMS** | Study + selection stub → **always falls back to fbdev** in this mission |
| **Wayland** | Architecture/docs only — **not** a compositor |

Env: `RYOKU_DISPLAY_BACKEND=fbdev|drm` (drm → FALLBACK=1).

Serial announces `DISPLAY …`, DRM study note, and `WAYLAND=ARCH_ONLY`.

## Related

- [`../architecture/RYOKU_DESKTOP_ARCHITECTURE.md`](../architecture/RYOKU_DESKTOP_ARCHITECTURE.md)
