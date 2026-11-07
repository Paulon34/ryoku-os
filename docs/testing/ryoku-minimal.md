# Ryoku Minimal — first usable experimental environment (Mission 012 FINAL)

## Honesty

| Claim | Meaning |
|-------|---------|
| Interactive path wired | `ryoku-init` (PID 1) may spawn `ryoku-console` **after** READY when `/bin/ryoku-console` exists |
| Experimental initramfs layout | `/init`, `/bin/ryoku-console`, `/dev/console`, `/etc/ryoku-release`, `/home/ryoku/` |
| Host unit/integration tests | Parser, FS confinement (symlinks rejected), initramfs structure, init gating |
| Static musl + Minimal cpio + lab kernel package | Built on disposable GHA (`ryoku-minimal-package`) |
| Real QEMU guest session | Script ready; **NOT_RUN** unless separately authorized |
| Full OS / Desktop / persistence | **Not** claimed |

Ryoku Minimal is a **lab interactive path**, not a product OS.

## Architecture

```
QEMU (TCG, nic=none, serial=stdio)     # console-interactive.rvl.conf
  └─ lab kernel + ryoku-minimal.cpio.gz
       ├─ /init              → ryoku-init (PID 1)
       │     1. announce pid=1 + RYOKU_BOOT_SEED_READY
       │     2. if /bin/ryoku-console present → spawn once
       │        (sets RYOKU_CONSOLE_ROOT=/)
       │     3. reap child; idle forever (never exit; no auto-restart)
       └─ /bin/ryoku-console → limited REPL on /dev/console
             builtins: help version status echo clear pwd ls cat
```

### Separation from original T3

| Artifact | Initrd | Console binary | Serial |
|----------|--------|----------------|--------|
| `t3-boot-seed.rvl.conf` | `ryoku-boot-seed.cpio.gz` | **absent** → idle after READY | file log |
| `console-interactive.rvl.conf` | `ryoku-minimal.cpio.gz` | **present** → spawn after READY | stdio |

`RYOKU_BOOT_SEED_READY` is emitted **only** by `ryoku-init` when `pid == 1`.

## Experimental filesystem

- Host: requires validated `RYOKU_CONSOLE_ROOT` (never falls back to host `/`).
- Guest: PID 1 exports `RYOKU_CONSOLE_ROOT=/`.
- Symlinks rejected on every path component; `cat` reads capped at 65536 (+1 detect).
- Residual TOCTOU between `lstat` and open documented in `ryoku-console/src/fs.rs`.
- Literal `!` allowed in echo args (no history expansion).

## Commands

```bash
# Host tests
cd zaquion-core && cargo fmt --check && cargo test --workspace && cargo clippy --workspace -- -D warnings

# Dry-run pack / QEMU plan
tests/qemu/scripts/build-ryoku-minimal-initramfs.sh
tests/qemu/scripts/prep-ryoku-minimal-artifacts.sh
tests/qemu/scripts/run-ryoku-minimal-qemu.sh   # plan+validate; QEMU NOT_RUN

# CI package workflow: .github/workflows/ryoku-minimal-package.yml
# VM README: tests/qemu/README-VM.md
```

Authorized guest (separate human auth — not this publish step):

```bash
RYOKU_MINIMAL_QEMU_EXECUTE=1 RYOKU_MINIMAL_QEMU_CONFIRM=RUN \
  tests/qemu/scripts/run-ryoku-minimal-qemu.sh
```

## Related

- [console.md](console.md) · [boot-seed.md](boot-seed.md) · [boot-seed-t3.md](boot-seed-t3.md)
- [ADR-0002](../architecture/ADR-0002.md)
- [README-VM.md](../../tests/qemu/README-VM.md)
