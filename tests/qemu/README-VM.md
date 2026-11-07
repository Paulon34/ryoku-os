# Ryoku Minimal — VM-ready package (Mission 012 FINAL)

## Honesty

| Claim | Status |
|-------|--------|
| Static musl `ryoku-init` + `ryoku-console` | Built on disposable CI |
| `ryoku-minimal.cpio.gz` experimental initramfs | Packed on disposable CI |
| Lab kernel `ryoku-boot-seed-vmlinuz` | Extracted from verified Alpine virt channel (ADR-0002) |
| Interactive QEMU guest boot | **NOT_RUN** in Mission 012 FINAL publish (script ready) |
| Product OS / Desktop | **Not** claimed |
| T3 Boot Seed evidence path | **Preserved** (`ryoku-boot-seed.cpio.gz` + file serial) |

## Artifacts (download from GitHub Actions)

| File | Role |
|------|------|
| `ryoku-boot-seed-vmlinuz` | Temporary lab kernel (not a Ryoku kernel fork) |
| `ryoku-minimal.cpio.gz` | Minimal initramfs with `/init` + `/bin/ryoku-console` |
| `ryoku-minimal-SHA256SUMS.txt` | Digests |
| `run-ryoku-minimal-qemu.sh` | Plan/validate by default; QEMU only with auth env |
| `README-VM.md` | This file |

## Linux host — plan / validate (no guest)

```bash
# After downloading artifacts into tests/qemu/run/ (+ results/SUMS):
tests/qemu/scripts/run-ryoku-minimal-qemu.sh
```

## Linux host — authorized interactive guest (future)

```bash
# Requires qemu-system-x86_64 on a disposable/authorized machine:
RYOKU_MINIMAL_QEMU_EXECUTE=1 RYOKU_MINIMAL_QEMU_CONFIRM=RUN \
  tests/qemu/scripts/run-ryoku-minimal-qemu.sh
```

Expected serial: `ryoku-init: pid=1` → `RYOKU_BOOT_SEED_READY` → console banner → `ryoku>`.

QEMU shape: TCG, 256 MB, 1 CPU, `-nic none`, no host disks, `-display none -serial stdio -monitor none`.

## Guest FS

PID 1 sets `RYOKU_CONSOLE_ROOT=/`. Builtins: help, version, status, echo, clear, pwd, ls, cat.
Symlinks rejected; `cat` capped at 64 KiB. Residual TOCTOU after lstat documented in `ryoku-console/src/fs.rs`.

## Related

- `docs/testing/ryoku-minimal.md`
- Profile: `tests/qemu/configs/console-interactive.rvl.conf`
- T3 (separate): `tests/qemu/configs/t3-boot-seed.rvl.conf`
