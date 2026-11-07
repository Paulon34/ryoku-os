# Reference Linux for First Boot Lab (Missions 005–006)

## Critical distinction

| Claim | Allowed when |
|-------|----------------|
| **Harness can start QEMU** | Emulator binary present; T1 may PASS |
| **Reference Linux booted** | Authorized Alpine image present, **all** serial markers matched, logs retained |
| **Ryoku OS booted** | **Never** from this reference image — Ryoku has **no ISO** yet |

> **Reference Linux boot ≠ Ryoku OS boot.**  
> Alpine here is a **third-party probe guest** to validate serial capture, timeouts, and shutdown. It does **not** choose Alpine (or Ubuntu) as the definitive Ryoku userland base (still **not formalized** — see ADR-0001 / compatibility docs).

> **QEMU process start ≠ Linux boot success.** PASS requires guest serial evidence with Alpine-specific markers.

## Selected image

| Field | Value |
|-------|--------|
| Distro | **Alpine Linux** (virt ISO) |
| Version | **3.21.9** (pinned; bump only with documented justification) |
| Arch | **x86_64** |
| File | `alpine-virt-3.21.9-x86_64.iso` |
| URL | `https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/alpine-virt-3.21.9-x86_64.iso` |
| SHA-256 | `1ceafa2ca068faf2925de977815681c182708f3c6cbfbad137f3ffc9324a03b4` |
| SHA file | `…/alpine-virt-3.21.9-x86_64.iso.sha256` |
| Signature | `…/alpine-virt-3.21.9-x86_64.iso.asc` |
| GPG key | `https://alpinelinux.org/keys/ncopa.asc` |
| GPG fingerprint | `0482 D840 22F5 2DF1 C4E7 CD43 293A CD09 07D9 495A` |
| Local path (after fetch) | `tests/qemu/run/alpine-virt-3.21.9-x86_64.iso` (gitignored) |
| Manifest | `tests/qemu/fixtures/reference-image.manifest` |

**Why Alpine virt?** Small official ISO, serial-friendly, widely used for QEMU smoke tests. Alternatives (Debian cloud, Fedora cloud) remain valid later — none are “the Ryoku base” until an ADR says so.

**License:** Third-party Alpine distribution; package licenses are mostly GPL/MIT/BSD. Redistribute only under Alpine’s terms. Not a Ryoku component license. **Never commit the ISO to git.**

## Acceleration (Mission 006)

| Host | Accel |
|------|-------|
| Disposable GHA `ubuntu-24.04` (Mission 006) | Config forces **`accel = tcg`** (no KVM required) |
| Local host with usable `/dev/kvm` | May use KVM only if config is changed + authorized |
| Cursor / personal hosts | **Do not install QEMU** for this mission |

## Download + verify

Default script mode is **dry-run** (prints URLs/commands; does not write the ISO):

```bash
tests/qemu/scripts/fetch-reference-image.sh
```

Authorized execute (**disposable runner only** after review):

```bash
RYOKU_FETCH_EXECUTE=1 RYOKU_VERIFY_GPG=1 tests/qemu/scripts/fetch-reference-image.sh
```

Verification steps (abort on mismatch):

1. HTTPS host allowlist (`dl-cdn.alpinelinux.org` for ISO/checksum/sig; `alpinelinux.org` for key)
2. Official `.sha256` lists the pinned digest
3. ISO bytes match pinned SHA-256
4. Detached `.asc` verifies with Alpine `ncopa` key fingerprint pin

Never run an unverified image.

## Serial markers (PASS criteria)

Config `tests/qemu/configs/t2-reference-alpine.rvl.conf`:

- `boot_markers = Alpine|login:` — **all** must appear in captured serial
- Evidence written to `tests/qemu/results/verified-boot-evidence.json`

Harness-only / simulated strings do **not** count.

### If ISO boot does not forward to serial

Document the failure in the mission report. A safe follow-up is an official Alpine **kernel + initramfs** reference boot (still Alpine upstream artifacts, still ≠ Ryoku), with the same SHA/GPG rules — evaluate only after ISO serial path is proven insufficient.

## GitHub Actions (`first-boot.yml`)

- Trigger: **`workflow_dispatch` only** (no push / PR auto-run)
- Manual gate: input `confirm` must equal `RUN`
- Runner: `ubuntu-24.04`, timeout 35m, `permissions: contents: read`
- Installs `qemu-system-x86` / `qemu-utils` / `gnupg` from **Ubuntu apt only**
- Downloads Alpine **only** on that disposable runner
- Uploads `tests/qemu/results/` (+ checksum/sig sidecars) as artifacts — no secrets

**Milestone (Mission 007.1):** verified reference boot **PASS** on Actions run
[`42319912088`](https://github.com/Paulon34/ryoku-os/actions/runs/42319912088)
(`main` @ `b65c3bc`, Alpine virt 3.21.9, QEMU TCG, serial `Alpine` + `login:`).
That remains **reference Linux**, not Ryoku OS.

## Exact plan to run first boot (after QEMU + image authorized)

```bash
# On disposable ubuntu-24.04 runner (or reviewed host — not Cursor):
# 1) apt install qemu-system-x86 qemu-utils gnupg
# 2) RYOKU_FETCH_EXECUTE=1 tests/qemu/scripts/fetch-reference-image.sh
# 3) From zaquion-core:
cargo run -p ryoku-virtlab -- t0
cargo run -p ryoku-virtlab -- first-boot
# 4) Inspect tests/qemu/results/verified-boot-evidence.json and serial-*.log
# 5) PASS only if markers matched; never rename that to “Ryoku booted”
```

## Related

- [virtual-lab.md](virtual-lab.md)
- [qemu-strategy.md](qemu-strategy.md)
- Config: `tests/qemu/configs/t2-reference-alpine.rvl.conf`
- Workflow: `.github/workflows/first-boot.yml`
