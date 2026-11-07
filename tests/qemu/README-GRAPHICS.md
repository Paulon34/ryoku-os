# Ryoku Minimal — graphics preview package (Mission 014 / 014.1)

**Separate from** the serial Minimal VM zip (`README-VM.md` / `ryoku-minimal-package`).

## Honesty / status matrix

| Claim | Status |
|-------|--------|
| Musl build of init + console + `ryoku-graphics-demo` | CI package (expect **PASS**/FAIL from workflow) |
| Pinned Alpine virt DRM modules (12 allowlisted `.ko`) | CI package (checksum + vermagic gated) |
| `ryoku-graphics.cpio.gz` + SHA256SUMS (+ module provenance) | CI package |
| Lab kernel (Alpine virt 6.12.114-0-virt, ADR-0002) | Same verified extract channel |
| Graphics driver inspection (`hw graphics`) | Host fixtures **PASS**; guest **`PASS_MANUAL`** on tip `8355f68` (PCI only; DRM absent) |
| First graphical boot | **`NOT_RUN`** |
| `FIRST_PIXELS` visual proof | **`NOT_RUN`** (never auto-PASS) |
| Product Desktop / 3D | **Not** claimed |
| Serial 013 package | **Unchanged** / not replaced |

### Lab kernel graphics notes

- Graphics profile adds `-device virtio-vga` + windowed `-display gtk|sdl,gl=off` while keeping `-serial stdio`.
- Alpine `linux-virt` ships DRM/fb as **modules**. 014.1 packs the **exact matching** netboot-3.21.9 modloop allowlist into the **graphics** cpio only (never NixOS host modules; never 6.12.115 mixed with 6.12.114).
- PID1 graphics profile loads allowlisted modules via `finit_module`, then starts `/bin/ryoku-graphics-demo` once (**WARN + continue** to serial console on failure).
- PCI `virtio-pci` alone ≠ loaded `virtio_gpu` DRM. Prefer real `/dev/fb0`; DRM-without-fb is reported honestly (no unpresented buffer claim).

## Download → extract → validate

1. Green `ryoku-graphics-package` Actions run.
2. Artifact `ryoku-graphics-vm-<sha>`.
3. Extract; run plan-only:

```bash
chmod +x run-ryoku-graphics-qemu.sh
./run-ryoku-graphics-qemu.sh
```

## Future authorized execute (manual NixOS / disposable)

```bash
# dual gate — never auto
RYOKU_GRAPHICS_QEMU_EXECUTE=1 RYOKU_GRAPHICS_QEMU_CONFIRM=RUN \
  ./run-ryoku-graphics-qemu.sh

# optional: RYOKU_GRAPHICS_DISPLAY=sdl|gtk|none
```

After boot, expect serial stages from PID1/demo (`device discovered` / `driver ready` /
`surface available` / `presented successfully`). Confirm the **QEMU window** shows
Ryoku title pixels (not SeaBIOS). `hw graphics` remains available on the serial console.
**`FIRST_PIXELS=PASS` only after your visual confirmation.**

## Related

- `docs/testing/ryoku-graphics.md`
- Module pin: `tests/qemu/fixtures/virt-drm-modules.manifest`
- Fetch (dry-run by default): `tests/qemu/scripts/fetch-virt-drm-modules.sh`
- Serial package: `README-VM.md`
