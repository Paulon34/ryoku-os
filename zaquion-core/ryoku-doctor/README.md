# ryoku-doctor

Read-only host diagnostics for **Ryoku OS** / **Zaquion Core** development.

## What it does

Prints **OK / WARN / FAIL** for developer tools:

| Check | Importance | Notes |
|-------|------------|-------|
| OS / arch | required | Linux expected for full OS workflows |
| `rustc`, `cargo` | required | Needed to build this workspace |
| `git`, `rustfmt`, Clippy, Clang, `llvm-config`, Make | optional | WARN if missing |
| QEMU / `/dev/kvm` | optional | WARN if missing or inaccessible — **never** fails Rust CI |

The tool **never** uses sudo, installs packages, changes permissions, or touches disks/firmware.

## Build & run

From the Cargo workspace root (`zaquion-core/`):

```bash
cargo build -p ryoku-doctor
cargo run -p ryoku-doctor
cargo test -p ryoku-doctor
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
```

Binary: `target/debug/ryoku-doctor` (after `cargo build`).

## Dependencies

**None** beyond the Rust standard library (Mission 002). Diagnostic logic is injected via traits so unit tests simulate command failures without a real QEMU install.

## License

Dual **MIT OR Apache-2.0** — see `../LICENSE-MIT` and `../LICENSE-APACHE`.
