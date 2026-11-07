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

### First-boot / T2 — reference Linux (Missions 005–007.1)

| Situation | `t2.reference_linux_boot` | `t2.ryoku_os_boot` |
|-----------|---------------------------|--------------------|
| QEMU absent | **SKIPPED** / **NOT_RUN** | **NOT_RUN** |
| QEMU present, ISO missing | **NOT_RUN** | **NOT_RUN** |
| QEMU + Alpine ISO + **all** `boot_markers` | **PASS**/**FAIL** with serial evidence JSON | **Always NOT_RUN** |

**Reference Linux boot ≠ Ryoku OS boot.** QEMU start ≠ Linux boot. See [reference-linux.md](reference-linux.md).

**Milestone:** Alpine virt 3.21.9 first-boot under QEMU TCG **PASS**ed on GitHub Actions
(run `42319912088`, Mission 007.1). That validates the harness only.

### Boot Seed / T3 — first-party init (Mission 008)

Separate QEMU profile from Alpine T2: temporary lab **kernel** + Ryoku **initramfs**
(`configs/t3-boot-seed.rvl.conf`). Opt-in via `ryoku-virtlab boot-seed` (not part of `all`).

| Situation | `t3.boot_seed` | `t3.ryoku_os_product_boot` |
|-----------|----------------|----------------------------|
| QEMU absent | **NOT_RUN** (after SKIPPED qemu case) | **NOT_RUN** |
| kernel/initrd missing | **NOT_RUN** | **NOT_RUN** |
| Guest serial has `RYOKU_BOOT_SEED_READY` | **PASS** | **Always NOT_RUN** |

See [boot-seed.md](boot-seed.md), [boot-seed-t3.md](boot-seed-t3.md), and
[ADR-0002](../architecture/ADR-0002.md).

Mission 009 adds: extract/prep dry-run scripts, manual `boot-seed-t3.yml`
(not dispatched), and harness env gate **`RYOKU_T3_EXECUTE=1`** before any
guest spawn. Real T3 still needs **separate authorization**.

**Never** claim Ryoku OS product boot from the seed alone.

### Interactive console / Ryoku Minimal (Mission 011–012)

Profile `configs/console-interactive.rvl.conf` sets `serial_log=stdio`,
`shutdown=none`, and Minimal initrd `ryoku-minimal.cpio.gz`. After READY,
`ryoku-init` may spawn `ryoku-console` when that binary is present. It does
**not** replace T3 file-serial evidence and guest boot is **not** executed in
Mission 012. See [console.md](console.md) and [ryoku-minimal.md](ryoku-minimal.md).

## Current environment limits (foundation host)

Recorded by `ryoku-doctor` / Mission 002–003:

- `qemu-system-x86_64`: typically **absent** → T1 SKIPPED
- `/dev/kvm`: may exist but be **unusable** for the CI/user → Auto selects TCG when QEMU exists
- No package installs / no KVM permission changes from this repo’s tooling

## Future use

| Target | How Virtual Lab helps |
|--------|------------------------|
| Boot seed (T3) | Kernel + `ryoku-init` initramfs; marker `RYOKU_BOOT_SEED_READY` |
| ISO / installer | Later tiers from `docs/testing/qemu-strategy.md` |
| UI / Desktop | Graphical steps only after headless smokes are green |

## Related

- [qemu-strategy.md](qemu-strategy.md)
- [`tests/qemu/README.md`](../../tests/qemu/README.md)
- Crate `zaquion-core/ryoku-virtlab`
