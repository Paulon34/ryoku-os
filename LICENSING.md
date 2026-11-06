# Licensing notice

Ryoku OS uses a **per-component** licensing strategy. There is intentionally **no** single root `LICENSE` that claims the entire tree is under one SPDX identifier.

See **[docs/licensing/strategy.md](docs/licensing/strategy.md)** for the full rationale, kernel GPLv2 obligations, and candidate licenses for Zaquion Core, docs, and packaging.

### First-party Rust (from Mission 002)

- `zaquion-core/` ships dual **MIT OR Apache-2.0**: `zaquion-core/LICENSE-MIT` and `zaquion-core/LICENSE-APACHE`.
- Crate metadata: `license = "MIT OR Apache-2.0"`.
- No third-party Rust crates were added as dependencies in Mission 002 (`ryoku-doctor` is stdlib-only).

Kernel and third-party packaging obligations are unchanged — see **[docs/licensing/strategy.md](docs/licensing/strategy.md)**.
