# Ryoku OS

**Ryoku OS** is an open-source Linux operating system focused on **OS + UX**: a stable kernel (upstream Linux), first-party Rust components (**Zaquion Core**), and a desktop experience to be ported later (**Ryoku Desktop**).

> Português: veja [README.md](README.md).

## Vision

| Layer | Role |
|-------|------|
| **Kernel** | Upstream Linux, unmodified initially; ready for future Rust integrations |
| **Zaquion Core** | First-party Rust system components, tools, and services |
| **Ryoku Desktop** | Existing GUI, separate project — integrate/port later |
| **Compatibility** | Nix, Debian, and Arch via integration and/or isolation |
| **Distribution** | Future ISO + installer; profiles Lite, Full, Gaming, Server |
| **Testing** | QEMU/KVM with progressive automation |

## Why this repository?

This monorepo (`ryoku-os`) holds the system foundation: architecture docs, space for Zaquion Core, future packaging, and the test harness. **Ryoku Desktop** and **ryoku-nixos** are conceptual sibling projects — preserved as external references; they are **not** invented or copied here.

## Structure (summary)

```
ryoku-os/                 ← root of this repository (/workspace)
├── zaquion-core/         # Rust: first-party services and tools
├── kernel/               # Upstream Linux reference (not vendored at this stage)
├── apps/                 # User apps (Desktop stays outside for now)
├── compatibility/        # Nix / Debian / Arch
├── packaging/            # ISO, installer, profiles
├── tests/                # QEMU/KVM harness (future)
└── docs/                 # Architecture, ADRs, licensing, testing
```

Layout decision: [docs/architecture/layout.md](docs/architecture/layout.md) · ADR: [docs/architecture/ADR-0001.md](docs/architecture/ADR-0001.md)

## Current status (Mission 002)

- Documentary foundation (Mission 001) + Cargo workspace under `zaquion-core/`
- `ryoku-doctor` CLI (read-only) + tests + GitHub Actions CI
- No kernel downloaded/built, no ISO, no VMs executed

### Zaquion / doctor

```bash
cd zaquion-core
cargo test --workspace
cargo run -p ryoku-doctor
```

See [zaquion-core/README.md](zaquion-core/README.md). Performance goals (not measurements): [docs/performance/targets.md](docs/performance/targets.md).

## Documentation

| Document | Content |
|----------|---------|
| [ROADMAP.md](ROADMAP.md) | Phases and next steps |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute |
| [SECURITY.md](SECURITY.md) | Vulnerability reporting |
| [docs/architecture/](docs/architecture/) | Overview and ADRs |
| [docs/testing/qemu-strategy.md](docs/testing/qemu-strategy.md) | QEMU test strategy |
| [docs/licensing/strategy.md](docs/licensing/strategy.md) | Licensing strategy |
| [docs/performance/targets.md](docs/performance/targets.md) | Preliminary performance targets |
| [docs/compatibility/](docs/compatibility/) | Nix / Debian / Arch |
| [zaquion-core/README.md](zaquion-core/README.md) | Rust workspace / MSRV / commands |

## Languages

Public docs in **Portuguese** and **English**. The primary `README.md` is Portuguese (project audience and name). This file is the English mirror.

## Licensing

There is **not** a single license for every component. The Linux kernel carries GPLv2 obligations; first-party components (Zaquion Core) and apps may use different licenses when compatibility is documented. See [docs/licensing/strategy.md](docs/licensing/strategy.md).

## Notice

This repository is foundational. Do not treat builds, ISOs, or images from here as production systems.

## Community

- Issues and PRs via GitHub (once the public remote is published)
- Templates under [`.github/`](.github/)
