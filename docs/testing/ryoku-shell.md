# Ryoku Shell Preview (Mission 015)

**Branch:** `cursor/ryoku-shell-015-927a` (stacked on Mission 014)  
**Graphical guest:** **`NOT_RUN`** until human visual confirm  
**Input (015.1):** **`NOT_RUN`**

## What this is

An original Ryoku illustrative desktop layout (navy/teal top panel, desktop area,
dock, status) drawn to a real `/dev/fb0` using the Mission **014.2** framebuffer
mmap/ioctl path. PID1 loads allowlisted DRM modules and starts
`/bin/ryoku-shell-preview` once (WARN + serial console on fail). The shell
package does **not** ship `ryoku-graphics-demo` (no dual FB fight).

## What this is not

- Not Wayland / Hyprland / XFCE / KDE / COSMIC
- Not a product Desktop or login session
- Not interactive (dock/panel are illustrative until evdev in 015.1)

## 015.1 input (planned — NOT_RUN)

Pointer/keyboard via Linux `evdev` on virtio-input (or equivalent), hit-testing
illustrative chrome, without claiming a full compositor. Documented here only;
**not implemented** in 015.

## Preserve

| Artifact | Status |
|----------|--------|
| T3 Boot Seed | Unchanged (no shell binary) |
| Serial Minimal | Unchanged |
| First Pixels graphics package | Unchanged; `FIRST_PIXELS=PASS_MANUAL` on tip `ca26ac5` |

## Related

- Package: [`tests/qemu/README-SHELL.md`](../../tests/qemu/README-SHELL.md)
- First Pixels: [ryoku-graphics.md](ryoku-graphics.md)
