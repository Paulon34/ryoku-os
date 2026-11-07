# ryoku-console

Interactive **Ryoku console** (Mission 011 / 012). Guest child of `ryoku-init`
in Ryoku Minimal; host REPL for prep/tests.

## Honesty

| Claim | Meaning |
|-------|---------|
| Host/unit tests of this crate | Parser + builtins + experimental FS work on the developer host |
| Guest spawn after READY | Wired in `ryoku-init` when `/bin/ryoku-console` exists (Minimal initramfs) |
| Interactive QEMU session | Prep profile only — **not** executed in Mission 012 |
| `t3.boot_seed` PASS | Still only `ryoku-init` PID 1 + `RYOKU_BOOT_SEED_READY` |
| Full Ryoku OS / login shell | **Not** claimed |

This crate is **separate from** `ryoku-init` PID 1. It must never emit READY as boot evidence.

## Builtins

| Command | Behavior |
|---------|----------|
| `help` | List builtins |
| `version` | Console package version + identity |
| `status` | Short readiness / honesty status |
| `echo …` | Echo arguments (no expansion) |
| `clear` | Emit ANSI clear + home |
| `pwd` | Experimental cwd |
| `ls [path]` | List directory (confined FS) |
| `cat path` | Read file capped (confined FS) |

## Limited parsing (security)

- No shell: no `|`, `&`, `;`, `` ` ``, `$`, redirects, quotes nesting, globs
- Tabs, CR, embedded newlines, and other controls are rejected (not stripped by `trim()`)
- Only ASCII spaces pad/separate tokens; max line / arg / argc caps
- Unknown commands rejected; empty input ignored
- `echo` reproduces args literally (not boot-seed evidence)
- FS path `..` cannot escape the experimental root

See [docs/testing/console.md](../../docs/testing/console.md) and
[docs/testing/ryoku-minimal.md](../../docs/testing/ryoku-minimal.md).

## Run (host dry REPL)

```bash
cd zaquion-core
cargo run -q -p ryoku-console
# optional: RYOKU_CONSOLE_ROOT=/path/to/staging cargo run -q -p ryoku-console
cargo test -p ryoku-console
```

Static musl guest binary (authorized builder):

```bash
cargo build -p ryoku-console --release --target x86_64-unknown-linux-musl
```
