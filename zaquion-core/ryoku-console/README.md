# ryoku-console

First interactive **Ryoku console** prototype (Mission 011).

## Honesty

| Claim | Meaning |
|-------|---------|
| Host/unit tests of this crate | Parser + builtins work on the developer host |
| Future interactive QEMU session | Prep profile only — **not** executed in Mission 011 |
| `t3.boot_seed` PASS | Still only `ryoku-init` PID 1 + `RYOKU_BOOT_SEED_READY` |
| Full Ryoku OS / login shell | **Not** claimed |

This crate is **separate from** `ryoku-init` PID 1. Mission 011 does **not** change READY/pid1 emission.

## Builtins

| Command | Behavior |
|---------|----------|
| `help` | List builtins |
| `version` | Console package version + identity |
| `status` | Short readiness / honesty status |
| `echo …` | Echo arguments (no expansion) |
| `clear` | Emit ANSI clear + home |

## Limited parsing (security)

- No shell: no `|`, `&`, `;`, `` ` ``, `$`, redirects, quotes nesting, globs
- Tabs, CR, embedded newlines, and other controls are rejected (not stripped by `trim()`)
- Only ASCII spaces pad/separate tokens; max line / arg / argc caps
- Unknown commands rejected; empty input ignored
- `echo` reproduces args literally (not boot-seed evidence)

See [docs/testing/console.md](../../docs/testing/console.md).

## Run (host dry REPL)

```bash
cd zaquion-core
cargo run -q -p ryoku-console
cargo test -p ryoku-console
```

Guest interactive boot is **not** part of this mission.
