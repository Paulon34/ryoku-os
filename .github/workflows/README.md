# GitHub Actions

## Active workflows (Mission 002)

| Workflow | File | Purpose |
|----------|------|---------|
| `ci` | [ci.yml](ci.yml) | Rust fmt, check, test, clippy on `zaquion-core/`; required doc path checks |

### Pins & permissions

- Rust toolchain: **1.83.0** (see `zaquion-core/rust-toolchain.toml` and `RUST_VERSION` in `ci.yml`)
- Actions: `actions/checkout@v4`, `dtolnay/rust-toolchain@master` (toolchain arg pinned), `Swatinem/rust-cache@v2`
- `permissions: contents: read` only

### Explicitly out of scope

- KVM availability (not assumed on `ubuntu-24.04` runners)
- QEMU boot / installer / graphical tests
- Kernel download or compile
- ISO build

`ryoku-doctor` runs in CI for signal; optional WARNs (no QEMU/KVM) must not fail the job unless a **required** check fails (doctor exit code semantics).
