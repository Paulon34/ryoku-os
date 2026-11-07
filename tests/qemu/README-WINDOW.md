# Ryoku Minimal — window system package (Mission 017)

Independent ZIP stacked on Mission 016.2 (PR #14 tip `5ee96b1`). Does **not** run QEMU in CI/agent.

| Check | Status |
|-------|--------|
| Musl init + console + shell-preview + WM | CI **PASS** (host) |
| Guest WM / launcher / input | **`GUEST_NOT_RUN`** until human |
| CONTROLLED_BENCHMARK guest | **NOT_RUN** (preserved) |
| Wayland / external apps | **Not** claimed |

## Manual

```bash
chmod +x run-ryoku-shell-qemu.sh
./run-ryoku-shell-qemu.sh
RYOKU_SHELL_QEMU_EXECUTE=1 RYOKU_SHELL_QEMU_CONFIRM=RUN ./run-ryoku-shell-qemu.sh
# Dock → Launcher → SYSTEM → WM DEMO window
```

## Docs

- `docs/testing/ryoku-window-system-017.md`
