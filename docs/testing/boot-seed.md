# Ryoku Boot Seed (Mission 008) — kernel + initramfs lab path

## Honesty

| Claim | Meaning |
|-------|---------|
| T2 Alpine PASS | Harness + reference Linux (completed Mission 007.1) |
| `t3.boot_seed` PASS | Guest serial has `ryoku-init: pid=1` **and** `RYOKU_BOOT_SEED_READY` (PID 1 only) |
| Ryoku OS product boot | **Not** claimed by the seed alone |

See [ADR-0002](../architecture/ADR-0002.md).

## Temporary kernel source (study — no download in Mission 008)

Prefer a kernel that is:

1. **Official / previously integrity-checked**, and
2. Suitable for QEMU virt (`x86_64`, serial console).

### Option A — Reuse verified Alpine virt channel (lab only)

The Mission 007.1 run verified Alpine virt **3.21.9** ISO:

- Origin: `https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/`
- SHA-256: `1ceafa2ca068faf2925de977815681c182708f3c6cbfbad137f3ffc9324a03b4`
- GPG: Alpine `ncopa` fingerprint `0482D84022F52DF1C4E7CD43293ACD0907D9495A`

A future authorized step may **extract** `boot/vmlinuz-virt` (and optionally
`boot/initramfs-virt`) from that ISO for T3 **kernel-only** reuse, then replace
initramfs with the Ryoku seed. License: third-party Alpine/Linux (GPLv2 kernel).
This does **not** adopt Alpine userland as Ryoku’s base.

### Option B — Official kernel.org (or distro `linux-image` with published hashes)

Pin a specific upstream release tarball or CI artifact with SHA-256 (+ signature
when a trust chain is documented). Heavier build; cleaner provenance for a
long-term lab kernel.

**Mission 008 does not download either.** Manifest:
`tests/qemu/fixtures/boot-seed-kernel.manifest`.

## Initramfs

Built by `tests/qemu/scripts/build-boot-seed-initramfs.sh` (dry-run default):

- Layout: `/init` → `ryoku-init` binary
- Format: `newc` cpio + gzip → `tests/qemu/run/ryoku-boot-seed.cpio.gz` (gitignored)
- No root, no host `/` modifications, no packing of host system files

### Static linking (critical)

Prefer `x86_64-unknown-linux-musl` for `/init`. The packer **fail-closes** on
dynamically linked binaries (Mission 008.5 audit). GNU builds remain OK for
**host** unit tests only. Documented in `zaquion-core/ryoku-init/README.md`.

### Console / devices

`append = console=ttyS0 earlyprintk=serial`. Initramfs ships empty `dev/`
(no `mknod`, no sudo). Lab kernels should provide `devtmpfs` so `/dev/console`
appears; `ryoku-init` also writes stdio.

## QEMU T3 profile (separate from Alpine T2)

Config: `tests/qemu/configs/t3-boot-seed.rvl.conf`

- `accel = tcg`, `network = none`
- `kernel = run/…`, `initrd = run/ryoku-boot-seed.cpio.gz`
- `append = console=ttyS0 earlyprintk=serial`
- `boot_markers = ryoku-init: pid=1|RYOKU_BOOT_SEED_READY` (serial-only)

## Future T3 procedure (requires separate authorization)

1. Obtain/pin kernel per Option A or B; verify hashes; place under `tests/qemu/run/`.
2. `cargo build -p ryoku-init --release` (musl static when available).
3. `RYOKU_INITRAMFS_EXECUTE=1 tests/qemu/scripts/build-boot-seed-initramfs.sh`
4. `cargo run -p ryoku-virtlab -- boot-seed` (or `t3`) on a host/runner with QEMU.
5. PASS only if **guest serial** contains both `ryoku-init: pid=1` and
   `RYOKU_BOOT_SEED_READY` (emitted only when the guest process is PID 1).
6. Still do **not** rename that to “Ryoku OS booted.”

Mission 008 stops before step 4 execution.
