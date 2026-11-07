# Ryoku Minimal — first usable experimental environment (Mission 012)

## Honesty

| Claim | Meaning |
|-------|---------|
| Interactive path wired | `ryoku-init` (PID 1) may spawn `ryoku-console` **after** READY when `/bin/ryoku-console` exists |
| Experimental initramfs layout | `/init`, `/bin/ryoku-console`, `/dev/console`, `/etc/ryoku-release`, `/home/ryoku/` |
| Host unit/integration tests | Parser, FS confinement, initramfs structure, init interactive gating |
| Real QEMU guest session | **Prep only** in Mission 012 — not executed |
| Full OS / Desktop / persistence | **Not** claimed |

Ryoku Minimal is a **lab interactive path**, not a product OS.

## Architecture

```
QEMU (TCG, nic=none, serial=stdio)     # console-interactive.rvl.conf
  └─ lab kernel + ryoku-minimal.cpio.gz
       ├─ /init              → ryoku-init (PID 1)
       │     1. announce pid=1 + RYOKU_BOOT_SEED_READY
       │     2. if /bin/ryoku-console present → spawn once
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
The console must not fake boot success.

## Experimental filesystem

Console `pwd` / `ls` / `cat` operate through a confined [`GuestFs`](../../zaquion-core/ryoku-console/src/fs.rs)
rooted at the initramfs (`/` in guest; temp root in tests). No writes, no external
shell, no persistence.

## Reproducible commands (no QEMU in Mission 012)

```bash
# Host tests
cd zaquion-core && cargo fmt --check && cargo test --workspace && cargo clippy --workspace -- -D warnings

# Dry-run Minimal pack + interactive prep
tests/qemu/scripts/build-ryoku-minimal-initramfs.sh
tests/qemu/scripts/prep-console-interactive.sh
tests/qemu/scripts/plan-minimal-guest-console-test.sh

# Future authorized pack (needs musl target on disposable builder):
# RYOKU_MINIMAL_INITRAMFS_EXECUTE=1 tests/qemu/scripts/build-ryoku-minimal-initramfs.sh
```

Example future QEMU argv (documented only — **do not run** here): see
`prep-console-interactive.sh` dry-run output / virtlab `serial_stdio` argv builder.

## Related

- [console.md](console.md) · [boot-seed.md](boot-seed.md) · [boot-seed-t3.md](boot-seed-t3.md)
- [ADR-0002](../architecture/ADR-0002.md)
