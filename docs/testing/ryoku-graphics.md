# Ryoku First Pixels (Mission 014 / 014.1)

**Evidence date (manual guest inspection):** 2026-11-07  
**Package tip inspected:** `8355f6839346dc836427a5c17ba9e7c7a84dc11b` (PR #8, pre-014.1 modules)  
**Env:** NixOS host; graphics ZIP; QEMU window + serial. **CI did not run this boot.**

## Status matrix

| Item | Status | Evidence class |
|------|--------|----------------|
| Host unit tests | **PASS** (expect CI) | Host / CI |
| Graphics package build | **PASS** (CI; 014.1 adds modules) | CI |
| **`graphics_guest_inspection`** | **`PASS_MANUAL`** | Paulo (≠ CI) |
| **`gpu_pci_discovery`** | **`PASS_MANUAL`** | `0000:00:02.0 driver=virtio-pci` |
| **`drm_kms`** | **`UNAVAILABLE_IN_OBSERVED_GUEST`** (tip `8355f68`) | no `/sys/class/drm`, `/dev/fb0`, `/dev/dri/*` |
| Window content (tip `8355f68`) | SeaBIOS firmware only (no Ryoku pixels) | Manual |
| **`FIRST_PIXELS`** | **`NOT_RUN` / `BLOCKED`** until DRM surface + **human visual confirm** | — |
| Product Desktop / 3D | **Not** claimed | — |

### Manual observations (tip `8355f68`)

- Boot / init / console **PASS**; QEMU window opened; `hw graphics` ran.
- PCI GPU `0000:00:02.0 driver=virtio-pci` — **not** proof `virtio_gpu` DRM is active (virtio-pci is the transport; DRM was modular/absent).
- Absent: `/sys/class/drm`, `/sys/class/graphics`, `/dev/fb0`, `/dev/dri/card0`, `/dev/dri/renderD128`.
- Do **not** claim first render PASS from PCI discovery or an unpresented software buffer.

## Kernel / modules investigation (014.1)

| Topic | Finding |
|-------|---------|
| Lab kernel | Alpine `6.12.114-0-virt` (ISO `alpine-virt-3.21.9`; sha256 `cf366215…`) |
| Matching modules | Alpine **netboot-3.21.9** `modloop-virt` (squashfs `modules/6.12.114-0-virt/…`); vermagic `6.12.114-0-virt SMP preempt…` |
| `virtio_gpu` | **Module** (`virtio-gpu.ko`), not built-in — explains PCI without `/dev/dri` |
| Dep closure | 12 allowlisted `.ko` (drm, kms_helper, fb, i2c-core, shmem helper, virtio_dma_buf, …) |
| `CONFIG_DRM*` / fbdev | Not plaintext in bzImage offline; operational evidence = matching modloop members (`virtio-gpu.ko` + fbdev helpers). Guest must mount **devtmpfs** for `/dev/fb0`/`/dev/dri/*`. |
| Host NixOS modules | **Forbidden** |
| Current CDN `linux-virt` APK | `6.12.115` — **must not** mix with `6.12.114` kernel |
| Provenance | Fetch pinned modloop URL + SHA-256; extract allowlist; record per-`.ko` SHA-256 + vermagic gate |

## 014.1 activation path (implemented)

1. `tests/qemu/scripts/fetch-virt-drm-modules.sh` — pinned modloop → allowlisted `.ko` (checksum + vermagic).
2. Graphics initramfs packs modules under `/lib/modules/6.12.114-0-virt/…` (serial Minimal package **unchanged**; keep old artifacts for T3/history).
3. PID1 **graphics profile only** (when `/bin/ryoku-graphics-demo` exists): after mounts, load allowlisted modules via `finit_module`, log device/driver/surface stages, start demo once; **WARN + continue** to console if gfx fails; never duplicate READY; no arbitrary module/exec paths from console.
4. Demo prefers real `/dev/fb0`; DRM card without fb → honest serial (`DrmOnlyNoFb`); no Wayland/desktop; dumb-buffer modeset deferred.
5. **`FIRST_PIXELS=PASS` only after human visual confirmation** — never auto. Report stays **`FIRST_PIXELS=NOT_RUN`** until then.

### Safest alternative if modules path blocked

Rebuild/lab a kernel with built-in `CONFIG_DRM_VIRTIO_GPU` + fbdev/devtmpfs and keep the same PID1/demo present path — still never invent PASS without pixels. Do not load NixOS host modules into the guest.

## Console / demo

- `hw graphics` — DRM/fb/`/dev`/PCI display-class inventory
- `hw pci` — class + bound driver basename or `unbound`
- `ryoku-graphics-demo` — static title on fb0 when surface exists; stage logs on serial

## Related

- [ryoku-hardware.md](ryoku-hardware.md) · [splash-prep-014.md](splash-prep-014.md)
- Package: [`tests/qemu/README-GRAPHICS.md`](../../tests/qemu/README-GRAPHICS.md)
- Module pin manifest: `tests/qemu/fixtures/virt-drm-modules.manifest`
