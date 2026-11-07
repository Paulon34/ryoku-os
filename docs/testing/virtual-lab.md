# Ryoku Virtual Lab — QEMU vs KVM vs TCG (Mission 003)

## Concepts

| Term | What it is | Role for Ryoku |
|------|------------|----------------|
| **QEMU** | User-space emulator/VMM that can run guest CPUs and devices | The process we spawn for Virtual Lab smokes |
| **KVM** | Linux kernel module + `/dev/kvm` for hardware-assisted virtualization | Fast acceleration when the host allows access |
| **TCG** | QEMU’s Tiny Code Generator — **software** CPU emulation | Fallback when KVM is missing or unusable (slower, CI-friendly) |

**QEMU ≠ KVM.** QEMU can run with `-accel tcg` without KVM. KVM without QEMU does nothing useful for this harness.

```
ryoku-virtlab
    → builds safe argv (no shell, no host disks)
        → qemu-system-x86_64
            → accel=kvm   if /dev/kvm usable
            → accel=tcg   otherwise (when QEMU exists)
```

## Harness phases

### T0 — always runnable (no QEMU required)

- Config parse/validate (`*.rvl.conf`)
- Block physical devices (`/dev/sd*`, `/dev/nvme*`, …)
- Reject path escapes and absolute host paths
- Safe argv construction
- Tool detection (report absence; do not fail T0 solely because QEMU is missing)
- CPU/RAM/timeout caps

### T1 — optional emulator

| Situation | `t1.emulator_start` | `t1.os_boot` |
|-----------|---------------------|--------------|
| QEMU absent | **SKIPPED** | **NOT_RUN** |
| QEMU present, emulator-only config | **PASS**/**FAIL** (spawn/timeout) | **NOT_RUN** (no guest image) |

### First-boot / T2 — reference Linux (Missions 005–006)

| Situation | `t2.reference_linux_boot` | `t2.ryoku_os_boot` |
|-----------|---------------------------|--------------------|
| QEMU absent | **SKIPPED** / **NOT_RUN** | **NOT_RUN** |
| QEMU present, ISO missing | **NOT_RUN** | **NOT_RUN** |
| QEMU + Alpine ISO + **all** `boot_markers` | **PASS**/**FAIL** with serial evidence JSON | **Always NOT_RUN** |

**Reference Linux boot ≠ Ryoku OS boot.** QEMU start ≠ Linux boot. See [reference-linux.md](reference-linux.md).

**Never** claim Ryoku OS booted without a bootable Ryoku kernel/system under test.

## Current environment limits (foundation host)

Recorded by `ryoku-doctor` / Mission 002–003:

- `qemu-system-x86_64`: typically **absent** → T1 SKIPPED
- `/dev/kvm`: may exist but be **unusable** for the CI/user → Auto selects TCG when QEMU exists
- No package installs / no KVM permission changes from this repo’s tooling

## Future use

| Target | How Virtual Lab helps |
|--------|------------------------|
| Kernel smoke | Attach disposable kernel under `tests/qemu/run/` + serial expectations |
| ISO / installer | Later T3/T4 from `docs/testing/qemu-strategy.md` |
| UI / Desktop | Graphical steps only after headless smokes are green |

## Related

- [qemu-strategy.md](qemu-strategy.md)
- [`tests/qemu/README.md`](../../tests/qemu/README.md)
- Crate `zaquion-core/ryoku-virtlab`
