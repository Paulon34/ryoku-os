# Ryoku Minimal — shell preview package (Mission 015)

**Separate from** First Pixels (`README-GRAPHICS.md`) and serial Minimal (`README-VM.md`).

## Honesty

| Claim | Status |
|-------|--------|
| Musl init + console + `ryoku-shell-preview` + DRM modules | CI **PASS** |
| **`SHELL_PREVIEW` tip `4b239a0`** | **`PASS_MANUAL`** (Paulo visual; ≠ CI) |
| Input (evdev / mouse / keyboard) | Mission **015.1** — **`NOT_RUN`** |
| Wayland / product Desktop | **Not** claimed |
| First Pixels (`FIRST_PIXELS=PASS_MANUAL`) | **Preserved** on graphics package |

## Download → plan → authorized execute

```bash
chmod +x run-ryoku-shell-qemu.sh
./run-ryoku-shell-qemu.sh
RYOKU_SHELL_QEMU_EXECUTE=1 RYOKU_SHELL_QEMU_CONFIRM=RUN \
  ./run-ryoku-shell-qemu.sh
```

## Related

- `docs/testing/ryoku-shell.md`
- First Pixels: `docs/testing/ryoku-graphics.md`
