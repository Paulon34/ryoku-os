# distro/core — Ryoku Debian Rust tools

Workspace (MIT OR Apache-2.0), separate from experimental desktop PRs `#6`–`#18`.

| Crate | Role |
|-------|------|
| `ryoku-cli` | `ryoku` binary: config / profile / system-info / jarvis-bridge |
| `ryoku-jarvis-bridge` | Opt-in Jarvis enablement (default off) |

```bash
cargo test --workspace
cargo run -p ryoku-cli -- --help
```
