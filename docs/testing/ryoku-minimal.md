# Ryoku Minimal — Mission 012 / 012.1 closeout

**Evidence date (manual guest):** 2026-11-07  
**Package tip used:** `fecc0b51c386b446ef7fac66da2181ab0b755dfa` (PR #6 / Mission 012.1 ZIP)  
**QEMU env (manual):** NixOS host; TCG; launcher dual-gate (`RYOKU_MINIMAL_QEMU_EXECUTE=1` + `RYOKU_MINIMAL_QEMU_CONFIRM=RUN`); shape from package (256 MB, 1 CPU, `-nic none`, no disks, `-serial stdio`).  
**CI did not run this boot.** Guest results below are **manual evidence only**.

## Honesty matrix

| Claim | Status | Evidence class |
|-------|--------|----------------|
| Host unit/integration tests | **PASS** — **130** lib tests (console 31 + doctor 19 + init 6 + virtlab 74) | Host / CI |
| `fmt` / `check` / `clippy -D warnings` | **PASS** | Host / CI |
| Static musl init + console | **PASS** (GHA package) | CI |
| Minimal initramfs + SHA256SUMS + lab kernel | **PASS** (GHA package + local zip verify) | CI + host |
| Self-contained ZIP launcher plan/hash | **PASS** | CI + host |
| **`interactive_guest_boot`** | **`PASS_MANUAL`** | Manual QEMU (Paulo), not CI |
| Product OS / Desktop boot | **NOT** proven | — |
| Original T3 Boot Seed evidence | **Separate** — unchanged; not this run | T3 path |
| `clear` builtin in guest | **NOT** proven | Do not mark PASS |

## Architecture (READY → optional console)

```
QEMU (TCG, 256MB, 1 CPU, -nic none, no disks)
  └─ lab kernel + ryoku-minimal.cpio.gz
       ├─ /init              → ryoku-init (PID 1)
       │     1. announce pid=1 + RYOKU_BOOT_SEED_READY
       │        (stdout + stderr + /dev/console — see known limits)
       │     2. if /bin/ryoku-console → spawn once (stdio→/dev/console;
       │        RYOKU_CONSOLE_ROOT=/)
       │     3. reap; idle forever (no auto-restart; PID 1 never exits)
       └─ /bin/ryoku-console → limited REPL
```

`RYOKU_BOOT_SEED_READY` is owned only by `ryoku-init` with `pid == 1`.

### T3 vs Minimal

| Artifact | Initrd | Console | Serial |
|----------|--------|---------|--------|
| `t3-boot-seed.rvl.conf` | `ryoku-boot-seed.cpio.gz` | absent → idle after READY | file log |
| `console-interactive.rvl.conf` | `ryoku-minimal.cpio.gz` | present → spawn after READY | stdio |

## Manual guest evidence (`PASS_MANUAL`)

Status key: **PASS** = observed on Paulo’s authorized QEMU run with the 012.1 ZIP.  
Not listed as PASS = not claimed.

### Boot / serial observations

| Observation | Status |
|-------------|--------|
| Lab kernel boot; `Run /init as init process` | observed |
| `ryoku-init: pid=1 seed=mission-008` | observed |
| `RYOKU_BOOT_SEED_READY` | observed |
| Spawn `/bin/ryoku-console`; `ryoku>` prompt | observed |
| READY/init announcement appears **three times** | observed (known limit) |
| Kernel messages can interrupt serial prompt visually | observed (known limit) |
| Product OS boot | **NOT** proven |
| CI executed this guest boot | **No** |

### Log excerpts (manual; paraphrased order)

```text
… kernel … Run /init as init process …
ryoku-init: pid=1 seed=mission-008
RYOKU_BOOT_SEED_READY
… (same announcement may repeat on duplicate channels) …
… spawning /bin/ryoku-console …
ryoku-console 0.1.0 — limited builtins; not a product OS shell
ryoku>
```

### Command matrix (guest REPL)

| Command | Result | Notes |
|---------|--------|-------|
| `help` | **PASS** | Builtin list shown |
| `version` | **PASS** | `0.1.0` |
| `pwd` | **PASS** | `/home/ryoku` |
| `ls /` | **PASS** | Root listing |
| `ls /etc` | **PASS** | Includes `ryoku-release` |
| `cat /etc/ryoku-release` | **PASS** | `ryoku-minimal 0.1.0 (Mission 012)` |
| `status` | **PASS** | Honesty blurb |
| `sudo` | **PASS** (reject) | Unknown command; returned to `ryoku>` |
| `\` (forbidden) | **PASS** (reject) | Rejected; returned to prompt |
| `echo …!` | (usability kept; not re-listed as guest matrix row here) | Literal `!` allowed on host tests |
| `clear` | **NOT** proven | Do **not** mark PASS |
| `hw …` | N/A in 012 | Mission 013 |

## Residual risks / known limits

| Item | Detail |
|------|--------|
| **TOCTOU** | Symlink reject then open race — documented in `ryoku-console/src/fs.rs` |
| **READY thrice** | `announce()` mirrors to stdout, stderr, and `/dev/console` → serial may show READY 3× |
| **Serial interleave** | Kernel printk can visually interrupt the REPL prompt |
| **Literal `!`** | Allowed in `echo` (no history expansion) |
| **Three console FDs** | Child opens `/dev/console` separately for stdin/stdout/stderr |
| **No proc/sys mount in 012** | Hardware probe nodes may be absent until Mission 013 |
| **T3 isolation** | This manual run is **not** T3 evidence |

## Host / CI commands actually demonstrated (agent + GHA)

```bash
cd zaquion-core
cargo fmt --check && cargo check --workspace && cargo test --workspace
cargo clippy --workspace -- -D warnings
# → 130 lib tests PASS

tests/qemu/scripts/run-ryoku-minimal-qemu.sh          # plan-only
tests/qemu/scripts/test-ryoku-minimal-vm-zip.sh       # standalone layout
# Downloaded artifact @ fecc0b5: sha256sum -c; ./run-ryoku-minimal-qemu.sh → standalone OK
```

## Re-run checklist (ZIP)

```bash
unzip ryoku-minimal-vm-*.zip && chmod +x run-ryoku-minimal-qemu.sh
./run-ryoku-minimal-qemu.sh    # validate hashes — never starts QEMU
RYOKU_MINIMAL_QEMU_EXECUTE=1 RYOKU_MINIMAL_QEMU_CONFIRM=RUN \
  ./run-ryoku-minimal-qemu.sh  # authorized guest only
```

Suggested guest checks (already **PASS_MANUAL** once): `help` `version` `pwd` `ls /` `ls /etc` `cat /etc/ryoku-release` `status`.

## Related

- [console.md](console.md) · [boot-seed.md](boot-seed.md) · [boot-seed-t3.md](boot-seed-t3.md)
- [README-VM.md](../../tests/qemu/README-VM.md) · [ADR-0002](../architecture/ADR-0002.md)
- PR #6 · artifact tip `fecc0b5`
