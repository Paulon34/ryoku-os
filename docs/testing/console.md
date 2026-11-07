# Ryoku console — interactive prototype (Mission 011 / 012)

## Honesty

| Claim | Meaning |
|-------|---------|
| `ryoku-console` builtins on host | Parser + help/version/status/echo/clear/pwd/ls/cat unit-tested |
| Interactive QEMU profile | `console-interactive.rvl.conf` uses `serial_log=stdio` |
| Guest wiring after READY | Mission 012: PID 1 spawns console when `/bin/ryoku-console` exists |
| **`interactive_guest_boot`** | **`PASS_MANUAL`** (2026-11-07) — Paulo’s authorized QEMU + 012.1 ZIP; **not** CI |
| Proven guest builtins | `help` `version` `pwd` `ls /` `ls /etc` `cat /etc/ryoku-release` `status`; rejects `sudo` and forbidden `\` |
| `clear` in guest | **NOT** proven |
| T3 Boot Seed PASS | Still `ryoku-init: pid=1` + `RYOKU_BOOT_SEED_READY` on **file** serial — **separate** path |
| Product OS / login shell | **Not** claimed |
| Residual risks | TOCTOU; READY×3 channels; serial printk interleave; literal `!` in echo |

Full matrix + log excerpts: [ryoku-minimal.md](ryoku-minimal.md).

`ryoku-console` remains a **separate crate** from `ryoku-init`. Only `ryoku-init`
emits READY as PID 1.

## Builtins (012 + 013)

- `help` — list commands  
- `version` — console version  
- `status` — honesty / readiness blurb (explicitly not product boot)  
- `echo …` — print args with **no** expansion (`!` literal allowed)  
- `clear` — ANSI clear screen (**guest NOT proven**)  
- `pwd` / `ls` / `cat` — experimental FS (guest **PASS_MANUAL** for listed paths)  
- `hw summary` / `hw cpu` / `hw pci` / `hw drivers` — read-only probe (Mission 013; **guest NOT_RUN**)

## Limited parsing (security)

Fail-closed:

- Reject shell metacharacters: `| & ; \` $ > < ( ) { } [ ] * ? ~ \ ' "`, NULs, tabs, CR, embedded newlines, and other C0/DEL controls
- Leading/trailing padding is ASCII space (`' '`) only — never `str::trim()`
- ASCII-only; max line 256 bytes; max 16 args; max 128 bytes/arg
- No pipes, redirects, substitution, globs, or nested quotes
- Unknown commands rejected (no `/bin/sh` fallback) — guest: `sudo` → unknown
- `echo` may reproduce user-supplied text (including the READY marker string) — that is not boot evidence
- FS builtins cannot escape the experimental root (`..` rejected); symlinks rejected

## QEMU profiles

| Profile | Initrd | Serial | Role |
|---------|--------|--------|------|
| `t3-boot-seed.rvl.conf` | `ryoku-boot-seed.cpio.gz` | file log | Authorized T3 evidence — **unchanged** |
| `console-interactive.rvl.conf` | `ryoku-minimal.cpio.gz` | `stdio` | Interactive Minimal — **PASS_MANUAL** once (not CI) |

## Related

- [ryoku-minimal.md](ryoku-minimal.md) · [boot-seed.md](boot-seed.md) · [boot-seed-t3.md](boot-seed-t3.md) · [ADR-0002](../architecture/ADR-0002.md)
- Crate: `zaquion-core/ryoku-console/`
