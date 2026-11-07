# Ryoku Minimal — self-contained VM package (Mission 012.1)

## Honesty

| Claim | Status |
|-------|--------|
| Static musl `ryoku-init` + `ryoku-console` | Built on disposable CI |
| `ryoku-minimal.cpio.gz` experimental initramfs | Packed on disposable CI |
| Lab kernel `ryoku-boot-seed-vmlinuz` | Verified Alpine virt channel (ADR-0002) |
| Interactive QEMU guest boot (012.1) | **`PASS_MANUAL`** (tip `fecc0b5`); **not** CI |
| Hardware probe guest (013) | **`PASS_MANUAL`** (tip `649b850`); **not** CI — see `docs/testing/ryoku-hardware.md` |
| Product OS / Desktop / first pixels | **Not** claimed / **NOT_RUN** |
| T3 Boot Seed evidence path | **Preserved** / separate (not required to use this ZIP) |
| Launcher banner text | Still says “Mission 012.1” for ZIP compat — behavior is dual-mode + hash gate |

## Download → extract → validate

1. Open the green `ryoku-minimal-package` Actions run for the PR/commit.
2. Download artifact `ryoku-minimal-vm-<sha>` (zip).
3. Extract to any directory (no git clone required):

```bash
mkdir -p ~/ryoku-minimal-vm && cd ~/ryoku-minimal-vm
unzip /path/to/ryoku-minimal-vm-*.zip
# Expected beside each other:
#   ryoku-boot-seed-vmlinuz
#   ryoku-minimal.cpio.gz
#   SHA256SUMS.txt
#   run-ryoku-minimal-qemu.sh
#   README-VM.md
#   console-interactive.rvl.conf
#   bin-musl/ryoku-init  bin-musl/ryoku-console
```

4. **Validate** (plan-only — never starts QEMU):

```bash
chmod +x run-ryoku-minimal-qemu.sh
./run-ryoku-minimal-qemu.sh
```

The launcher auto-detects **standalone** mode when `SHA256SUMS.txt` + kernel + initrd
sit next to the script. It **always** verifies `SHA256SUMS.txt` and fails closed on
missing/mismatched files. Standalone mode does **not** need T3/repo files.

### Repo-tree mode (developers)

From a full checkout after CI/local pack placed blobs under `tests/qemu/run/`
(with `tests/qemu/run/SHA256SUMS.txt`):

```bash
tests/qemu/scripts/run-ryoku-minimal-qemu.sh
```

## Authorized execute (manual)

Requires `qemu-system-x86_64` on a disposable/authorized machine:

```bash
RYOKU_MINIMAL_QEMU_EXECUTE=1 RYOKU_MINIMAL_QEMU_CONFIRM=RUN \
  ./run-ryoku-minimal-qemu.sh
```

Both env vars are required. Shape: TCG, 256 MB, 1 CPU, `-nic none`, no host disks,
`-display none -serial stdio -monitor none`.

Expected serial: `ryoku-init: pid=1` → `RYOKU_BOOT_SEED_READY` → console → `ryoku>`.  
Manual run (2026-11-07) confirmed that path with command matrix in
[`docs/testing/ryoku-minimal.md`](../../docs/testing/ryoku-minimal.md)
(`interactive_guest_boot=PASS_MANUAL`). CI still does **not** execute guest boot.

## Package contents

| File | Role |
|------|------|
| `ryoku-boot-seed-vmlinuz` | Temporary lab kernel |
| `ryoku-minimal.cpio.gz` | Minimal initramfs (`/init` + `/bin/ryoku-console`) |
| `SHA256SUMS.txt` | Digests (verified before every run) |
| `run-ryoku-minimal-qemu.sh` | Plan/validate by default; QEMU gated |
| `README-VM.md` | This file |
| `bin-musl/*` | Static musl ELFs (inspection / rebuild inputs) |

## Related

- `docs/testing/ryoku-minimal.md`
- Workflow: `.github/workflows/ryoku-minimal-package.yml`
