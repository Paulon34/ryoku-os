# `ryoku-init` — Ryoku Boot Seed / Minimal PID 1 (Mission 008 / 012 / 013 / 014.1)

Minimal **PID 1** prototype for early QEMU smoke tests. Emits
`RYOKU_BOOT_SEED_READY` **only when `pid == 1`**. Non-PID-1 invocations print a
diagnostic (no READY) and exit non-zero. Virtual Lab **T3** requires guest serial
`ryoku-init: pid=1` **and** `RYOKU_BOOT_SEED_READY` — **not** Alpine reference boot,
and **not** a finished Ryoku OS.

Announcements use a **single channel** (prefer `/dev/console`, else stdout once)
to avoid READY×3 when stdout/stderr/console share a UART.

### Interactive mode (Mission 012/013 — separate from T3)

After READY, if `/bin/ryoku-console` exists (Ryoku Minimal initramfs), PID 1:

1. Mounts `proc` → `/proc`, `sysfs` → `/sys`, and `devtmpfs` → `/dev` (WARN on failure; does not abort)
2. Prints a plain ASCII honesty banner
3. **Graphics profile (014.1):** if `/bin/ryoku-graphics-demo` exists, load allowlisted
   Alpine virt DRM modules via `finit_module`, then start the demo **once**
   (WARN + continue on failure; never duplicates READY; never claims `FIRST_PIXELS=PASS`)
4. Spawns the console **once** with stdin/stdout/stderr on `/dev/console`
5. Reaps the child, then idles forever

Original Boot Seed initramfs lacks the console binary → **exact** prior T3
idle-after-READY behavior (**no** mounts, **no** banner). Serial Minimal omits the
graphics demo → no module load. Console/demo exit/EOF/failure must **not** kill
PID 1; there is **no** uncontrolled restart loop.

## Build (dev / tests)

```bash
cd zaquion-core
cargo build -p ryoku-init
cargo test -p ryoku-init
```

## Static linking (initramfs) — required for real T3

Initramfs must ship a **statically linked** `init`. A glibc/gnu PIE binary needs
`/lib64/ld-linux-x86-64.so.2` + `libc.so.6`, which this minimal initramfs does
**not** include. The packer **refuses** dynamic binaries via `check-static-elf` (ELF byte analysis;
**not** `ldd`). `RYOKU_INITRAMFS_ALLOW_DYNAMIC=1` is **blocked** for guest packing.

```bash
rustup target add x86_64-unknown-linux-musl
# Disposable builder may also need a musl linker (e.g. musl-tools)
cargo build -p ryoku-init --release --target x86_64-unknown-linux-musl
file target/x86_64-unknown-linux-musl/release/ryoku-init   # expect "statically linked"
```

Release builds use `panic = "abort"` (workspace) so PID 1 does not unwind away.

### Guest console

QEMU profile sets `append = console=ttyS0 earlyprintk=serial`. Prefer a lab
kernel with `CONFIG_DEVTMPFS` (+ mount) so `/dev/console` exists; `ryoku-init`
opens `/dev/console` when present for announce + child stdio.

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
