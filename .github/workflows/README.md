# GitHub Actions

## Active workflows (Missions 002–003)

| Workflow | File | Purpose |
|----------|------|---------|
| `ci` | [ci.yml](ci.yml) | Rust fmt/check/test/clippy; `ryoku-doctor`; Virtual Lab `ryoku-virtlab all`; doc path checks |

### Pins & permissions

- Rust toolchain: **1.83.0**
- Actions: `actions/checkout@v4`, `dtolnay/rust-toolchain@master`, `Swatinem/rust-cache@v2`
- `permissions: contents: read` only

### Virt policy

- **Does not** require QEMU or KVM on runners
- T0 must PASS; T1 **SKIPPED** / OS boot **NOT_RUN** without QEMU/guest image — exit 0
- No kernel/ISO/boot jobs
