# Ryoku Minimal — graphics preview package (Mission 014 / 014.1 / 014.2)

**Separate from** the serial Minimal VM zip (`README-VM.md` / `ryoku-minimal-package`).

## Honesty / status matrix

| Claim | Status |
|-------|--------|
| Musl build + DRM modules pack | CI **PASS** |
| `FIRST_PIXELS` tip `08baa45` | **`FAIL_MANUAL`** (file-size mmap) |
| 014.2 mmap fix | explicit validated `MmapOptions::len` + ioctl |
| **`FIRST_PIXELS` tip `ca26ac5`** | **`PASS_MANUAL`** (Paulo visual; ≠ CI) |
| Product Desktop / 3D | **Not** claimed |
| Serial 013 package | **Unchanged** |

## Download → validate → authorized execute

1. Artifact `ryoku-graphics-vm-<sha>` from `ryoku-graphics-package`.
2. Plan-only: `./run-ryoku-graphics-qemu.sh`
3. Dual gate (manual NixOS):

```bash
RYOKU_GRAPHICS_QEMU_EXECUTE=1 RYOKU_GRAPHICS_QEMU_CONFIRM=RUN \
  ./run-ryoku-graphics-qemu.sh
```

## Related

- `docs/testing/ryoku-graphics.md`
- Module pin: `tests/qemu/fixtures/virt-drm-modules.manifest`
