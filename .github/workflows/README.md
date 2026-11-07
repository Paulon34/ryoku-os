# GitHub Actions

## Active workflows

| Workflow | File | Purpose |
|----------|------|---------|
| `ci` | [ci.yml](ci.yml) | Rust fmt/check/test/clippy; Virtual Lab `all` (T0–T2); doc paths |
| `first-boot` | [first-boot.yml](first-boot.yml) | Manual `confirm=RUN` — Alpine T2 reference boot (≠ Ryoku OS) |
| `boot-seed-t3` | [boot-seed-t3.yml](boot-seed-t3.yml) | Manual `confirm=RUN` — Boot Seed T3 (Mission 009+; **do not dispatch** until authorized) |

### Pins & permissions

- Rust toolchain: **1.83.0**
- Actions: `actions/checkout@v4`, `dtolnay/rust-toolchain@master`, `Swatinem/rust-cache@v2`
- `permissions: contents: read` only

### Virt policy

- **CI** does not require QEMU/KVM; T0 PASS; T1/T2 SKIPPED/NOT_RUN without tools/ISO
- Manual first-boot / boot-seed-t3: disposable `ubuntu-24.04` only; guest net off; TCG
- Boot Seed guest also requires harness env `RYOKU_T3_EXECUTE=1`
- Never claim Ryoku OS product boot from Alpine T2 or Boot Seed T3 alone
