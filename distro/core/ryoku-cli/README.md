# ryoku-cli

Operator CLI for the Ryoku Debian track (`distro/`).

```bash
cd distro/core
cargo test --workspace
cargo run -p ryoku-cli -- system-info
cargo run -p ryoku-cli -- jarvis-bridge status
```

Jarvis is **off by default**. Enable only intentionally:

```bash
ryoku jarvis-bridge enable
# or RYOKU_JARVIS=1
```
