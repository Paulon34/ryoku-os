# Ryoku First Pixels (Mission 014)

## Status matrix

| Item | Status |
|------|--------|
| Host unit tests (hwprobe graphics + software blit) | **PASS** (local/CI) |
| Graphics package workflow (musl + cpio + plan-only) | see CI |
| Graphics driver inspection (guest) | **NOT_RUN** |
| First graphical boot | **NOT_RUN** |
| `FIRST_PIXELS` | **NOT_RUN** |
| Mission 013 serial guest | **`PASS_MANUAL`** (separate) |

## Investigation summary (no invented driver PASS)

| Topic | Finding |
|-------|---------|
| Current serial profile PCI | Chipset IDs only (`8086:1237/7000/7010/7113`) — **no** display class |
| Lab kernel | Alpine `vmlinuz-virt` (e.g. 6.12.114-0-virt); bzImage notes “Normal VGA”; **no** embedded `CONFIG_DRM=*` string extract in offline scan |
| Modules | Not bundled in Minimal/graphics cpio; matching `linux-virt` modules **not** vendored this mission |
| Path forward | QEMU `-device virtio-vga` + window; `devtmpfs` mount; `hw graphics`; fb0 demo when node exists |

## Console

- `hw graphics` — DRM/fb/`/dev`/PCI display-class inventory (honest ERR/missing)
- `hw pci` — includes **class** label + **bound driver** symlink basename or `unbound`

## Demo

`ryoku-graphics-demo`: static title (“RYOKU OS / Minimal Developer Preview / Rust Userland”) into software buffer; present via `/dev/fb0` mmap when geometry exists. Clear serial error otherwise. Never auto-marks FIRST_PIXELS=PASS.

## Related

- [ryoku-hardware.md](ryoku-hardware.md) · [splash-prep-014.md](splash-prep-014.md)
- Package README: [`tests/qemu/README-GRAPHICS.md`](../../tests/qemu/README-GRAPHICS.md)
