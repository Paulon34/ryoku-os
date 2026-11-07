# `ryoku-shell-preview` — Mission 015 / 015.1

Illustrative **desktop layout** drawn to a real `/dev/fb0` using the Mission
014.2 framebuffer mmap/ioctl path. Mission **015.1** keeps the process alive
with a guest-evdev event loop (cursor, dock hit-test, launcher panel).

Not a product Desktop. Not Wayland. Not Bash / Hyprland.

## Honesty

| Claim | Status |
|-------|--------|
| Software layout + present to fb0 when surface exists | Host unit / package |
| Guest shell preview visual | Mission **015** — **`SHELL_PREVIEW=PASS_MANUAL`** (closeout) |
| Guest input (`INPUT_GUEST` / mouse / keyboard) | Mission **015.1** — **`NOT_RUN`** until human |
| Product shell / compositor / app exec | **Not** claimed |

## Build

```bash
cd zaquion-core
cargo test -p ryoku-shell-preview
cargo build -p ryoku-shell-preview --release --target x86_64-unknown-linux-musl
```
