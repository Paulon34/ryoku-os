# Ryoku Boot Seed — kernel + initramfs lab path

## Honesty

| Claim | Meaning |
|-------|---------|
| T2 Alpine PASS | Harness + reference Linux (completed Mission 007.1) |
| Prep / dry-run (Mission 009) | Scripts + workflow file ready — **no** guest T3 |
| `t3.boot_seed` PASS | Guest serial has `ryoku-init: pid=1` **and** `RYOKU_BOOT_SEED_READY` (PID 1 only) |
| Ryoku OS product boot | **Not** claimed by the seed alone |

See [ADR-0002](../architecture/ADR-0002.md) and [boot-seed-t3.md](boot-seed-t3.md).

## Temporary kernel source

Prefer a kernel that is:

1. **Official / previously integrity-checked**, and
2. Suitable for QEMU virt (`x86_64`, serial console).

### Option A — Reuse verified Alpine virt channel (lab only)

The Mission 007.1 run verified Alpine virt **3.21.9** ISO:

- Origin: `https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/`
- SHA-256: `1ceafa2ca068faf2925de977815681c182708f3c6cbfbad137f3ffc9324a03b4`
- GPG: Alpine `ncopa` fingerprint `0482D84022F52DF1C4E7CD43293ACD0907D9495A`
- ISO member: **`boot/vmlinuz-virt`**

Safe extract (no host disk mounts): `tests/qemu/scripts/extract-boot-seed-kernel.sh`  
(dry-run default; uses `isoinfo` / `xorriso` on disposable builders).

License: third-party Alpine/Linux (GPLv2 kernel). This does **not** adopt Alpine
userland as Ryoku’s base.

### Option B — Official kernel.org

Pin a specific upstream release with SHA-256 (+ signature when documented).

**Mission 009 does not download either on Cursor.** Manifest:
`tests/qemu/fixtures/boot-seed-kernel.manifest`.

## Initramfs

- Script: `tests/qemu/scripts/build-boot-seed-initramfs.sh` (dry-run default)
- Orchestration + hashes: `tests/qemu/scripts/prep-boot-seed-artifacts.sh`
- Layout: `/init` → static `ryoku-init`; `/dev/console` char **5:1** (newc metadata)
- Output: `tests/qemu/run/ryoku-boot-seed.cpio.gz` (gitignored)

### Static linking (critical)

Prefer `x86_64-unknown-linux-musl`. Packer fail-closes on dynamic ELFs via
`check-static-elf` (exec `PT_LOAD`, no `PT_INTERP`/`DT_NEEDED`; **not** `ldd`).
`RYOKU_INITRAMFS_ALLOW_DYNAMIC=1` is blocked for guest packing.

## QEMU T3 profile

Config: `tests/qemu/configs/t3-boot-seed.rvl.conf`

- `accel = tcg`, `network = none`
- `kernel` / `initrd` under `run/`
- `boot_markers = ryoku-init: pid=1|RYOKU_BOOT_SEED_READY` (serial-only)

### Accidental-run guard (Mission 009)

Guest spawn requires **`RYOKU_T3_EXECUTE=1`**. Without it, `t3.boot_seed` stays
**NOT_RUN** even if assets exist. `ryoku-virtlab all` never includes T3.

### Interactive console (Mission 011)

A separate profile `console-interactive.rvl.conf` uses `serial_log=stdio` for a
future interactive session. It **must not** replace this T3 file-serial profile.
Console code lives in `ryoku-console` (not PID 1). See [console.md](console.md).

## Authorized T3 procedure (separate mission / human auth)

1. Dispatch `.github/workflows/boot-seed-t3.yml` with `confirm=RUN` on `main` only after review.
2. Runner fetches ISO (SHA+GPG), extracts `boot/vmlinuz-virt`, builds musl init, packs initramfs.
3. `RYOKU_T3_EXECUTE=1 cargo run -p ryoku-virtlab -- boot-seed`
4. PASS only from **guest serial** markers above; product boot stays NOT_RUN.

Mission 009 stops before step 1 dispatch.
