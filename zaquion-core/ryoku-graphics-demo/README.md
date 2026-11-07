# ryoku-graphics-demo (Mission 014 — First Pixels)

Static software text blit onto `/dev/fb0` when a real framebuffer is present.

## Honesty

| Claim | Status |
|-------|--------|
| Software RGB buffer + glyph blit (host unit tests) | Intended **PASS** |
| Present to `/dev/fb0` when node + sysfs geometry exist | Attempted at runtime |
| DRM/KMS modeset / virtio-gpu 3D | **Not** implemented |
| `FIRST_PIXELS` visual guest proof | **`NOT_RUN`** until recorded manually |
| Product Desktop | **Not** claimed |

Env: `RYOKU_GRAPHICS_ROOT` (optional) confines device/sysfs paths for fixtures —
never opens ambient host `/dev/fb0` unless root is `/` (guest).
