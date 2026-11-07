# `ryoku-shell-preview` — Mission 015 / 015.2 / 016 / **016.1**

Illustrative **desktop layout** + **Ryoku Launcher** on `/dev/fb0` (Mission 014.2
mmap/ioctl). Adaptive profiles Lite/Balanced/Ultra; Mission **016.1** adds
compose/present instrumentation and optional perf overlay.

Not a product Desktop. Not Wayland. Not Bash / Hyprland. No app exec. No blur/3D.

## Honesty

| Claim | Status |
|-------|--------|
| Software layout + launcher + present to fb0 | Host unit / package |
| Fact indicators (`UNAVAILABLE` / `DETECTED` / `EVENTS RECEIVED`) | Runtime facts only |
| Guest launcher / mouse / keyboard / perf confirm | **`NOT_RUN`** / **`GUEST_NOT_RUN`** until human |
| Auto `PASS_MANUAL` / invented timings from CI | **Never** |
| QEMU TCG = hardware | **No** |

## Perf (016.1)

- Serial metrics ~5s: selected→effective, compose/present µs, scratch KiB
- Band compose for cursor dirty (no full-frame gradient on every move)
- Skip mmap flush on partial blit (set `RYOKU_SHELL_FLUSH_PARTIAL=1` to force)
- Overlay: `RYOKU_SHELL_PERF_OVERLAY=1` (**off by default**)

## Build

```bash
cd zaquion-core
cargo test -p ryoku-shell-preview
cargo build -p ryoku-shell-preview --release --target x86_64-unknown-linux-musl
```
