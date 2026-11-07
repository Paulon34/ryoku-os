# Ryoku First Pixels (Mission 014 / 014.1 / 014.2)

## Status matrix

| Item | Status | Evidence class |
|------|--------|----------------|
| Host unit tests | **PASS** (expect CI) | Host / CI |
| Graphics package build | **PASS** (CI) | CI |
| **`graphics_guest_inspection`** (tip `8355f68`) | **`PASS_MANUAL`** | Paulo |
| **`gpu_pci_discovery`** (tip `8355f68`) | **`PASS_MANUAL`** | `0000:00:02.0 driver=virtio-pci` |
| **`graphics_driver`** (tip `08baa45`) | **`PASS_MANUAL`** | 12/12 DRM mods; `virtio_gpu` |
| **`framebuffer_available`** (tip `08baa45`) | **`PASS_MANUAL`** | dri + fb0 + drm class; FB 941×474 32bpp stride 3764 |
| **`graphics_demo_started`** (tip `08baa45`) | **`PASS_MANUAL`** | demo ran |
| **`FIRST_PIXELS`** (tip `08baa45` / 014.1 attempt) | **`FAIL_MANUAL`** | blit: `mmap shorter than stride*height`; SeaBIOS/black window |
| **`FIRST_PIXELS`** (post-014.2) | **`NOT_RUN`** until human visual confirm | — |
| Product Desktop / 3D | **Not** claimed | — |

### Manual observations — tip `8355f68` (pre-modules)

- Boot / init / console **PASS**; QEMU window opened; `hw graphics` ran.
- PCI GPU `0000:00:02.0 driver=virtio-pci` — **not** proof `virtio_gpu` DRM.
- Absent: `/sys/class/drm`, `/sys/class/graphics`, `/dev/fb0`, `/dev/dri/*`.

### Manual observations — tip `08baa45` (014.1 modules; FAIL_MANUAL pixels)

- **Env:** NixOS host; graphics ZIP; QEMU window + serial. **CI did not run this boot.**
- 12/12 DRM modules loaded; `virtio_gpu` active; dri + fb0 + drm sysfs present.
- Demo started; FB **941×474** 32bpp stride **3764**.
- **FAIL:** `blit failed: mmap shorter than stride*height` — root cause: file-size `mmap` of `/dev/fb0` (char device, size 0) instead of explicit validated length.
- Window: SeaBIOS / black — **do not** mark FIRST_PIXELS=PASS.

## Kernel / modules (014.1 — unchanged in 014.2)

| Topic | Finding |
|-------|---------|
| Lab kernel | Alpine `6.12.114-0-virt` |
| Matching modules | Alpine netboot-3.21.9 `modloop-virt` (12 allowlisted `.ko`) |
| Host NixOS modules | **Forbidden** |
| 014.2 | **No** Alpine kernel/module set change |

## 014.2 framebuffer mmap fix (implemented)

1. Prefer `FBIOGET_VSCREENINFO` / `FBIOGET_FSCREENINFO`; sysfs fallback for fixtures.
2. Validate width/height/bpp/stride/overflows/capacity (`smem_len`, `MAX_FB_MAP_BYTES`).
3. `MmapOptions::len(validated)` — **never** file-size mmap of fb0.
4. Software title buffer sized to FB (safe for non-640×480); blit clipped; no write past visible capacity.
5. Diagnostics: capacity, requested/obtained mmap len, format, errors.
6. Software buffer alone ≠ present; `FIRST_PIXELS` never auto-PASS. PID1 still WARN+continues to serial console on demo fail.

## Related

- Package: [`tests/qemu/README-GRAPHICS.md`](../../tests/qemu/README-GRAPHICS.md)
- Module pin: `tests/qemu/fixtures/virt-drm-modules.manifest`
