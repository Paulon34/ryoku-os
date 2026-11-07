# `ryoku-shell-preview` — Mission 015 / 015.1 / 015.2

Illustrative **desktop layout** + **Ryoku Launcher** on `/dev/fb0` (Mission 014.2
mmap/ioctl). Guest-evdev event loop with ABS caps, device filter, and
fact-based input indicators.

Not a product Desktop. Not Wayland. Not Bash / Hyprland. No app exec.

## Honesty

| Claim | Status |
|-------|--------|
| Software layout + launcher + present to fb0 | Host unit / package |
| Fact indicators (`UNAVAILABLE` / `DETECTED` / `EVENTS RECEIVED`) | Runtime facts only |
| Guest launcher / mouse / keyboard confirm | **`NOT_RUN`** until human |
| Auto `PASS_MANUAL` from CI | **Never** |

## Build

```bash
cd zaquion-core
cargo test -p ryoku-shell-preview
cargo build -p ryoku-shell-preview --release --target x86_64-unknown-linux-musl
```
