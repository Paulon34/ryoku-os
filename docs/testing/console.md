# Ryoku console — first interactive prototype (Mission 011)

## Honesty

| Claim | Meaning |
|-------|---------|
| `ryoku-console` builtins on host | Parser + help/version/status/echo/clear unit-tested |
| Interactive QEMU profile | **Prep only** — `console-interactive.rvl.conf` uses `serial_log=stdio` |
| T3 Boot Seed PASS | Still `ryoku-init: pid=1` + `RYOKU_BOOT_SEED_READY` on **file** serial |
| Product OS / login shell | **Not** claimed |

`ryoku-console` is a **separate crate** from `ryoku-init`. Mission 011 does not
change PID 1 READY emission or replace the T3 file-serial profile.

## Builtins

- `help` — list commands  
- `version` — console version  
- `status` — honesty / readiness blurb (explicitly not product boot)  
- `echo …` — print args with **no** expansion  
- `clear` — ANSI clear screen  

## Limited parsing (security)

Fail-closed:

- Reject shell metacharacters: `| & ; \` $ > < ( ) { } [ ] * ? ~ \ ' "`, NULs, tabs, CR, embedded newlines, and other C0/DEL controls
- Leading/trailing padding is ASCII space (`' '`) only — never `str::trim()` (that would hide tabs/CR)
- ASCII-only; max line 256 bytes; max 16 args; max 128 bytes/arg
- Line I/O: capped `fill_buf`/`consume` reader (`MAX_LINE_BYTES` + small margin); overflow drains to LF without copying the long line; CRLF may span fills; invalid UTF-8 rejected
- No pipes, redirects, substitution, globs, or nested quotes
- Unknown commands rejected (no `/bin/sh` fallback)
- `echo` may reproduce user-supplied text (including the READY marker string) — that is not boot evidence

## QEMU profiles

| Profile | Serial | Role |
|---------|--------|------|
| `t3-boot-seed.rvl.conf` | `results/serial-t3-boot-seed.log` (file) | Authorized T3 evidence — **unchanged** |
| `console-interactive.rvl.conf` | `stdio` | Interactive prep — **not** executed in Mission 011 |

`serial_log=stdio` requires `shutdown=none` so QEMU does not put both monitor and
serial on stdio.

Dry-run: `tests/qemu/scripts/prep-console-interactive.sh`  
(`RYOKU_CONSOLE_INTERACTIVE_EXECUTE=1` is refused in this mission.)

## Not in Mission 011

- Real guest boot / workflow dispatch / host package installs / ISO download  
- Push / PR / merge  
- Wiring `ryoku-console` as a guest process after READY  
- Claiming a full Ryoku OS is bootable  

## Related

- [boot-seed.md](boot-seed.md) · [boot-seed-t3.md](boot-seed-t3.md) · [ADR-0002](../architecture/ADR-0002.md)
- Crate: `zaquion-core/ryoku-console/`
