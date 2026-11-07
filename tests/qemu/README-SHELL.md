# Ryoku Minimal — shell preview package (Mission 015)

**Separate from** First Pixels (`README-GRAPHICS.md`) and serial Minimal (`README-VM.md`).

## Honesty

| Claim | Status |
|-------|--------|
| Musl init + console + `ryoku-shell-preview` + DRM modules | CI package |
| Shell layout on software buffer / fb0 when present | Host unit |
| Graphical shell guest | **`NOT_RUN`** until human visual confirm |
| Input (evdev / mouse / keyboard) | Mission **015.1** — **`NOT_RUN`** |
| Wayland / Hyprland / XFCE / KDE / COSMIC | **Not** claimed |
| First Pixels (`FIRST_PIXELS=PASS_MANUAL` on 014) | **Preserved** on graphics package |

Chrome (panel / dock / icons) is **illustrative** until 015.1 input.

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
