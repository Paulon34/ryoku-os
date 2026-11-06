# Reference Linux for First Boot Lab (Mission 005)

## Critical distinction

| Claim | Allowed when |
|-------|----------------|
| **Harness can start QEMU** | Emulator binary present; T1 may PASS |
| **Reference Linux booted** | Authorized Alpine (or other) image present, serial sentinel matched, logs retained |
| **Ryoku OS booted** | **Never** from this reference image — Ryoku has **no ISO** yet |

> **Reference Linux boot ≠ Ryoku OS boot.**  
> Alpine here is a **third-party probe guest** to validate serial capture, timeouts, and shutdown. It does **not** choose Alpine (or Ubuntu) as the definitive Ryoku userland base (still **not formalized** — see ADR-0001 / compatibility docs).

## Selected image

| Field | Value |
|-------|--------|
| Distro | **Alpine Linux** (virt ISO) |
| Version | **3.21.9** |
| Arch | **x86_64** |
| File | `alpine-virt-3.21.9-x86_64.iso` |
| URL | `https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/alpine-virt-3.21.9-x86_64.iso` |
| SHA-256 | `1ceafa2ca068faf2925de977815681c182708f3c6cbfbad137f3ffc9324a03b4` |
| SHA file | `…/alpine-virt-3.21.9-x86_64.iso.sha256` |
| Local path (after fetch) | `tests/qemu/run/alpine-virt-3.21.9-x86_64.iso` (gitignored) |
| Manifest | `tests/qemu/fixtures/reference-image.manifest` |

**Why Alpine virt?** Small official ISO, serial-friendly, widely used for QEMU smoke tests. Alternatives (Debian cloud, Fedora cloud) remain valid later — none are “the Ryoku base” until an ADR says so.

**License:** Third-party Alpine distribution; package licenses are mostly GPL/MIT/BSD. Redistribute only under Alpine’s terms. Not a Ryoku component license.

## Acceleration

| Host | Accel |
|------|-------|
| `/dev/kvm` usable | `accel = auto` → **KVM** |
| KVM missing / no permission | `accel = auto` → **TCG** (slower; expected on many CI hosts) |

This host (Mission 005 inspection): QEMU binary often **absent**; `/dev/kvm` may exist **without** user R/W — harness falls back to TCG **when** QEMU is installed. No KVM permission changes from tooling.

## Download + verify (do not run without authorization)

Default script mode is **dry-run** (prints URLs/commands; does not write the ISO):

```bash
tests/qemu/scripts/fetch-reference-image.sh
# or explicitly:
RYOKU_FETCH_EXECUTE=0 tests/qemu/scripts/fetch-reference-image.sh
```

Authorized execute (downloads into `tests/qemu/run/` and verifies SHA-256):

```bash
RYOKU_FETCH_EXECUTE=1 tests/qemu/scripts/fetch-reference-image.sh
```

Mission 005 **did not** download the ISO on the agent host.

## Exact plan to run first boot (after QEMU + image authorized)

```bash
# 1) Install QEMU on the host (manual / authorized — not done by repo scripts)
# 2) Fetch image with RYOKU_FETCH_EXECUTE=1
# 3) From zaquion-core:
cargo run -p ryoku-virtlab -- t0          # must stay green without QEMU
cargo run -p ryoku-virtlab -- first-boot  # SKIPPED/NOT_RUN until qemu+iso exist
# 4) Inspect tests/qemu/results/first-boot-*.txt and serial-*.log
# 5) PASS only if sentinel matched; never rename that to “Ryoku booted”
```

## Related

- [virtual-lab.md](virtual-lab.md)
- [qemu-strategy.md](qemu-strategy.md)
- Config: `tests/qemu/configs/t2-reference-alpine.rvl.conf`
