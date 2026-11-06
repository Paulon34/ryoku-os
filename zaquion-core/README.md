# Zaquion Core

First-party **Rust** components, tools, and (future) system services for Ryoku OS.

## Workspace layout

```
zaquion-core/
├── Cargo.toml              # workspace root
├── Cargo.lock              # locked for the doctor binary
├── LICENSE-MIT
├── LICENSE-APACHE
├── rust-toolchain.toml     # pinned toolchain for CI/dev alignment
├── README.md
└── ryoku-doctor/           # read-only host diagnostics CLI
```

## License

Dual **MIT OR Apache-2.0**, per [docs/licensing/strategy.md](../docs/licensing/strategy.md).

## MSRV (Minimum Supported Rust Version)

| Field | Value | Rationale |
|-------|-------|-----------|
| `rust-version` (Cargo) | **1.75** | Edition 2021 + stable std APIs used by `ryoku-doctor`; wide distro availability |
| Pinned toolchain (`rust-toolchain.toml` / CI) | **1.83.0** | Matches the Mission 001/002 Cloud Agent image; reproducible CI |

We do **not** require bleeding-edge language features. Raising MSRV needs a short note in the PR and an update here.

## Build / test commands

```bash
cd zaquion-core
cargo check --workspace
cargo test --workspace
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo run -p ryoku-doctor
```

Missing QEMU or KVM access may make the doctor print **WARN**; that is expected and must not fail `cargo test`.

## Crates

| Crate | Kind | Role |
|-------|------|------|
| `ryoku-doctor` | bin (+ lib) | Host diagnostics (Mission 002) |

No privileged system services and no kernel code live here yet.
