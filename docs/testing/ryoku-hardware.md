# Ryoku hardware probe (Mission 013)

## Honesty

| Claim | Status |
|-------|--------|
| Host unit tests (`ryoku-hwprobe` fixtures + console `hw *`) | **PASS** (CI / local) |
| PID 1 mounts `proc` + `sysfs` after READY, before console (Minimal only) | Wired; WARN on fail; does not kill console |
| T3 READY contract / idle-after-READY | **Unchanged** (no mounts when console binary absent) |
| Single-channel READY announce | Wired (prefer `/dev/console`, else stdout once) |
| Guest QEMU hw probe after 013 package | **`NOT_RUN`** — do not invent results |
| Product drivers / Desktop / OS boot | **Not** claimed |
| 012.1 interactive guest | Separate evidence: **`PASS_MANUAL`** (see [ryoku-minimal.md](ryoku-minimal.md)) |

## Architecture

```
PID 1 (Minimal only, after READY):
  mount proc → /proc     (WARN on fail)
  mount sysfs → /sys     (WARN on fail)
  ASCII banner
  spawn ryoku-console (RYOKU_CONSOLE_ROOT=/ RYOKU_HWPROBE_ROOT=/)
       hw summary | hw cpu | hw pci | hw drivers
         └─ ryoku-hwprobe reads confined root (allows in-tree sysfs symlinks;
            rejects escapes; never implicit host /sys)
```

## Console commands

| Command | Role |
|---------|------|
| `hw summary` | CPU brief + pci count + tty preview + driver count |
| `hw cpu` | `/proc/cpuinfo` processors + model |
| `hw pci` | `/sys/bus/pci/devices/*/vendor|device` |
| `hw drivers` | `/sys/bus/*/drivers` listings |

Host without root → RootRequired. Missing nodes → honest `ERR` / missing messages (no fake PASS).

## Related

- Crate: `zaquion-core/ryoku-hwprobe/`
- [ryoku-minimal.md](ryoku-minimal.md) · [console.md](console.md)
- Splash prep (docs only): [splash-prep-014.md](splash-prep-014.md)
