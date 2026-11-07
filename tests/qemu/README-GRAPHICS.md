# Ryoku Minimal — graphics preview package (Mission 014)

**Separate from** the serial Minimal VM zip (`README-VM.md` / `ryoku-minimal-package`).

## Honesty / status matrix

| Claim | Status |
|-------|--------|
| Musl build of init + console + `ryoku-graphics-demo` | CI package (expect **PASS**/FAIL from workflow) |
| `ryoku-graphics.cpio.gz` + SHA256SUMS | CI package |
| Lab kernel (Alpine virt, ADR-0002) | Same verified extract channel |
| Graphics driver inspection (`hw graphics`) | Host fixtures **PASS**; guest inspection **NOT_RUN** here |
| First graphical boot | **`NOT_RUN`** |
| `FIRST_PIXELS` visual proof | **`NOT_RUN`** (never auto-PASS) |
| Product Desktop / 3D | **Not** claimed |
| Serial 013 package | **Unchanged** / not replaced |

### Lab kernel graphics notes (offline inspection)

- Serial Minimal QEMU uses `-nodefaults -display none` → often **no PCI display class** (chipset only).
- Graphics profile adds `-device virtio-vga` + windowed `-display gtk|sdl,gl=off` while keeping `-serial stdio`.
- Alpine `linux-virt` frequently ships DRM/fb as **modules**; Minimal/graphics cpio does **not** bundle matching modules in this mission (no host modules; no kernel rebuild claim).
- Therefore: virtio-vga PCI presence ≠ loaded DRM/KMS. `hw graphics` reports sysfs/`/dev` honestly.

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

After boot (if devices appear): `hw graphics`, then `/bin/ryoku-graphics-demo` from a future shell/helper —
demo prints clear serial errors if `/dev/fb0` missing; does **not** claim FIRST_PIXELS=PASS.

## Related

- `docs/testing/ryoku-graphics.md`
- Serial package: `README-VM.md`
