# `ryoku-init` — Ryoku Boot Seed (Mission 008)

Minimal **PID 1** prototype for early QEMU smoke tests. Prints a stable serial
marker `RYOKU_BOOT_SEED_READY` so Virtual Lab **T3** can verify a *Ryoku-owned*
guest process — **not** Alpine reference boot, and **not** a finished Ryoku OS.

## Build (dev / tests)

```bash
cd zaquion-core
cargo build -p ryoku-init
cargo test -p ryoku-init
```

## Static linking (initramfs)

Initramfs should ship a **static** `init` so the guest needs no dynamic linker.

Documented approach (when musl toolchain is available on a disposable builder):

```bash
rustup target add x86_64-unknown-linux-musl
# Debian/Ubuntu builder: apt install musl-tools
cargo build -p ryoku-init --release --target x86_64-unknown-linux-musl
```

This Cursor host typically has only `x86_64-unknown-linux-gnu`. Mission 008
packages whatever binary `cargo build -p ryoku-init --release` produces for
**structure tests**; a real T3 guest boot (separate authorization) should use
the musl static artifact.

## Initramfs

```bash
# Dry-run by default:
tests/qemu/scripts/build-boot-seed-initramfs.sh
# Execute (writes under tests/qemu/run/, gitignored):
RYOKU_INITRAMFS_EXECUTE=1 tests/qemu/scripts/build-boot-seed-initramfs.sh
```

## Honesty

| Claim | Allowed when |
|-------|----------------|
| Init binary builds / unit tests pass | Local `cargo test` |
| Initramfs contains `/init` | After authorized pack script |
| `t3.boot_seed` PASS | Separate T3 QEMU run with serial marker from guest |
| Ryoku OS product boot | **Never** from this seed alone |
