# Ryoku First Pixels (Mission 014 / 014.1 / 014.2) — CLOSED

**Closeout:** 2026-11-07 · tip **`ca26ac585f73a93ac7578c1f77f1f5f730ebbdba`** · PR #8  
**Official claim:** **`FIRST_PIXELS=PASS_MANUAL`** (Paulo NixOS QEMU visual confirm; **≠ CI**)

## Status matrix

| Item | Status | Evidence class |
|------|--------|----------------|
| Host unit tests / graphics package CI | **PASS** | CI |
| **`graphics_guest_inspection`** (tip `8355f68`) | **`PASS_MANUAL`** | Paulo |
| **`gpu_pci_discovery`** (tip `8355f68`) | **`PASS_MANUAL`** | `0000:00:02.0 driver=virtio-pci` |
| **`graphics_driver`** | **`PASS_MANUAL`** | 12/12 DRM mods; `virtio_gpu` |
| **`framebuffer_available`** | **`PASS_MANUAL`** | dri + fb0; 941×474 32bpp stride 3764 |
| **`FIRST_PIXELS`** (tip `08baa45` / 014.1) | **`FAIL_MANUAL`** | file-size mmap too short; SeaBIOS/black |
| **`FIRST_PIXELS`** (tip `ca26ac5` / 014.2) | **`PASS_MANUAL`** | visual title on QEMU window |
| Product Desktop / 3D / Wayland | **Not** claimed | — |

### Manual PASS — tip `ca26ac5` (014.2)

- Alpine virt boot; PID1 READY; 12/12 DRM modules; `virtio_gpu`; dri + fb0.
- FB **941×474** 32bpp; ioctl geometry; mmap requested/obtained **1784136**; presented successfully into `/dev/fb0` (exit 0); serial console continued.
- Screenshot description (human): **RYOKU OS / MINIMAL DEVELOPER PREVIEW / RUST USERLAND** — no hosted screenshot URL invented here.

### Manual FAIL history — tip `08baa45` (014.1) — preserved

- Same driver/fb path, then `blit failed: mmap shorter than stride*height` (file-size mmap of char-device fb0). Window SeaBIOS/black. Fixed in 014.2 via explicit `MmapOptions::len` + ioctl.

## Related

- Package: [`tests/qemu/README-GRAPHICS.md`](../../tests/qemu/README-GRAPHICS.md)
- Shell preview (015): separate package — does not replace First Pixels evidence
