# Ryoku Minimal — controlled performance package (Mission 016.2)

Independent ZIP stacked on Mission 016.1 (PR #13). Does **not** run QEMU in CI/agent.

| Check | Status |
|-------|--------|
| Musl init + console + shell-preview + DRM/input | CI **PASS** (host) |
| Guest controlled benchmark | **`CONTROLLED_BENCHMARK=NOT_RUN`** until human |
| Blur / 3D / Wayland compositor | **Not** claimed |
| QEMU TCG = physical | **No** |
| Invented / favored timings | **Never** |
| T3 boot-seed append | **Intact** (no `ryoku.*`) |

## Manual (NixOS)

```bash
chmod +x run-ryoku-shell-qemu.sh
./run-ryoku-shell-qemu.sh
RYOKU_CONTROLLED_BENCHMARK=1 RYOKU_DESKTOP_PROFILE=balanced \
  RYOKU_SHELL_QEMU_EXECUTE=1 RYOKU_SHELL_QEMU_CONFIRM=RUN \
  ./run-ryoku-shell-qemu.sh
```

## Docs

- `docs/testing/ryoku-adaptive-0162.md`
- Closeout 016.1: `docs/testing/ryoku-adaptive-0161.md`
