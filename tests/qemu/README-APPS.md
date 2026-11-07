# Ryoku Minimal — internal apps package (Mission 018)

Stacked on Mission 017. Does **not** run QEMU in CI/agent.

| Check | Status |
|-------|--------|
| Host musl package | CI **PASS** |
| Guest apps | **`GUEST_NOT_RUN`** |
| CONTROLLED_BENCHMARK guest | **NOT_RUN** |
| Arbitrary exec | **Not** claimed |

```bash
RYOKU_SHELL_QEMU_EXECUTE=1 RYOKU_SHELL_QEMU_CONFIRM=RUN ./run-ryoku-shell-qemu.sh
# Launcher categories open About / Monitor / Files RO / Settings
```
