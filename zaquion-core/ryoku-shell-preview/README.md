# `ryoku-shell-preview` — Mission 015

Illustrative **first desktop layout** drawn to a real `/dev/fb0` using the Mission
014.2 framebuffer mmap/ioctl path. Not a product Desktop. Not Wayland.

## Honesty

| Claim | Status |
|-------|--------|
| Software layout + present to fb0 when surface exists | Host unit / package |
| Graphical guest shell | **`NOT_RUN`** until human visual confirm |
| Pointer / keyboard input (evdev) | Mission **015.1** — **`NOT_RUN`** |
| Product shell / compositor | **Not** claimed |

Dock icons and panel controls are **illustrative** until input lands in 015.1.

## Build

```bash
cd zaquion-core
cargo test -p ryoku-shell-preview
cargo build -p ryoku-shell-preview --release --target x86_64-unknown-linux-musl
```
