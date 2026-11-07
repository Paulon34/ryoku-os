# ryoku-hwprobe (Mission 013)

Read-only hardware inventory helpers for Ryoku Minimal. Parses confined
`proc` / `sys` trees (guest `/` after mounts, or an explicit test fixture root).

## Honesty

| Claim | Status |
|-------|--------|
| Host unit tests with fixtures | Intended |
| Implicit host `/sys` / `/proc` | **Never** — root required |
| Guest QEMU hw probe | **NOT_RUN** until separately evidenced |
| Product driver stack | **Not** claimed |

Symlinks under sysfs are followed **only** when the resolved path stays under the
configured root (unlike experimental FS `pwd`/`ls`/`cat`, which reject all links).

## Env

Prefer `RYOKU_HWPROBE_ROOT`. If unset, callers may pass `RYOKU_CONSOLE_ROOT`.
Missing/invalid root → honest error string (no fake PASS).
