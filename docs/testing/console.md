# Ryoku console — interactive prototype (Mission 011 / 012)

## Honesty

| Claim | Meaning |
|-------|---------|
| `ryoku-console` builtins on host | Parser + help/version/status/echo/clear/pwd/ls/cat unit-tested |
| Interactive QEMU profile | **Prep only** — `console-interactive.rvl.conf` uses `serial_log=stdio` |
| Guest wiring after READY | Mission 012: PID 1 spawns console when `/bin/ryoku-console` exists |
| T3 Boot Seed PASS | Still `ryoku-init: pid=1` + `RYOKU_BOOT_SEED_READY` on **file** serial |
| Product OS / login shell | **Not** claimed |

`ryoku-console` remains a **separate crate** from `ryoku-init`. Only `ryoku-init`
emits READY as PID 1.

## Builtins

- `help` — list commands  
- `version` — console version  
- `status` — honesty / readiness blurb (explicitly not product boot)  
- `echo …` — print args with **no** expansion  
- `clear` — ANSI clear screen  
- `pwd` — experimental cwd (`/home/ryoku` when present)  
- `ls [path]` — list directory inside experimental FS  
- `cat path` — read file (capped) inside experimental FS  

## Limited parsing (security)

Fail-closed:

- Reject shell metacharacters: `| & ; \` $ > < ( ) { } [ ] * ? ~ \ ' "`, NULs, tabs, CR, embedded newlines, and other C0/DEL controls
- Leading/trailing padding is ASCII space (`' '`) only — never `str::trim()` (that would hide tabs/CR)
- ASCII-only; max line 256 bytes; max 16 args; max 128 bytes/arg
- Line I/O: capped `fill_buf`/`consume` reader (`MAX_LINE_BYTES` + small margin); overflow drains to LF without copying the long line; CRLF may span fills; invalid UTF-8 rejected
- No pipes, redirects, substitution, globs, or nested quotes
- Unknown commands rejected (no `/bin/sh` fallback)
- `echo` may reproduce user-supplied text (including the READY marker string) — that is not boot evidence
- FS builtins cannot escape the experimental root (`..` rejected)

## QEMU profiles

| Profile | Initrd | Serial | Role |
|---------|--------|--------|------|
| `t3-boot-seed.rvl.conf` | `ryoku-boot-seed.cpio.gz` | `results/serial-t3-boot-seed.log` | Authorized T3 evidence — **unchanged** |
| `console-interactive.rvl.conf` | `ryoku-minimal.cpio.gz` | `stdio` | Interactive Minimal — **not** executed in Mission 012 |

`serial_log=stdio` requires `shutdown=none` so QEMU does not put both monitor and
serial on stdio.

Dry-run: `tests/qemu/scripts/prep-console-interactive.sh`  
Guest test plan: `tests/qemu/scripts/plan-minimal-guest-console-test.sh`  
(`RYOKU_CONSOLE_INTERACTIVE_EXECUTE=1` / guest-test EXECUTE are refused here.)

## Related

- [ryoku-minimal.md](ryoku-minimal.md) · [boot-seed.md](boot-seed.md) · [boot-seed-t3.md](boot-seed-t3.md) · [ADR-0002](../architecture/ADR-0002.md)
- Crate: `zaquion-core/ryoku-console/`
