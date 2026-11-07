# Ryoku hardware probe (Mission 013) — closeout

**Evidence date (manual guest):** 2026-11-07  
**Package tip:** `649b850598141ffefd69f32252f74bb995915056` (PR #7 / artifact run `42400045637`)  
**QEMU env (manual):** NixOS host; TCG; self-contained ZIP; dual-gate launcher.  
**CI did not run this boot.** Status: **`guest_013=PASS_MANUAL`**.

## Honesty matrix

| Claim | Status | Evidence class |
|-------|--------|----------------|
| Host unit tests (`ryoku-hwprobe` + console `hw *`) | **PASS** | Host / CI |
| Static musl package + SHA256SUMS (GHA) | **PASS** | CI package |
| **`guest_013`** | **`PASS_MANUAL`** | Paulo QEMU (≠ CI) |
| Product OS / Desktop / driver stack | **Not** claimed | — |
| 012.1 interactive guest | Separate **`PASS_MANUAL`** | [ryoku-minimal.md](ryoku-minimal.md) |
| Mission 014 first pixels | **NOT_RUN** | [splash-prep-014.md](splash-prep-014.md) |

## Architecture (unchanged)

```
PID 1 (Minimal only, after READY):
  mount proc → /proc     (WARN on fail)
  mount sysfs → /sys     (WARN on fail)
  ASCII banner
  spawn ryoku-console (RYOKU_CONSOLE_ROOT=/ RYOKU_HWPROBE_ROOT=/)
       hw summary | hw cpu | hw pci | hw drivers
```

T3 idle-after-READY (no console binary) remains **without** mounts/banner.

## Manual guest evidence (`PASS_MANUAL`)

### Boot / mounts / announce

| Observation | Status |
|-------------|--------|
| `SHA256SUMS.txt` verify before run | **PASS** |
| Lab kernel Alpine **6.12.114-0-virt** boot | observed |
| `ryoku-init` as PID 1 | **PASS** |
| `RYOKU_BOOT_SEED_READY` appears **once** (single-channel announce) | **PASS** |
| `/proc` + `/sys` mounts OK (no mount-fail WARN) | **PASS** |
| ASCII honesty banner | **PASS** |
| Console spawn → `ryoku>` | **PASS** |
| No panic | observed |
| `clocksource` printk after first prompt | cosmetic (known serial interleave) |
| Launcher script header still says “Mission 012.1” | note only — keep compat; do not break ZIP tooling |

### Command matrix (guest)

| Command | Result | Notes |
|---------|--------|-------|
| `help` | **PASS** | |
| `version` | **PASS** | `0.1.0` |
| `hw summary` | **PASS** | |
| `hw cpu` | **PASS** | 1 vCPU; model `QEMU Virtual CPU version 2.5+` |
| `hw pci` | **PASS** | **4** devices: `8086:1237`, `8086:7000`, `8086:7010`, `8086:7113` |
| `hw drivers` | **PASS** | **10** sysfs PCI **driver directory names LISTED** — **not** a claim of 10 bound devices |
| `status` | **PASS** | Mission 013 honesty blurb |

### Honesty on `hw drivers`

`hw drivers` lists **names under** `/sys/bus/pci/drivers/` (and related buses). That is a
**sysfs directory listing**, not proof that N devices are bound to those drivers.
Do **not** rephrase “10 listed” as “10 device bindings.”

## Host / CI (demonstrated)

```bash
cd zaquion-core && cargo test --workspace && cargo clippy --workspace -- -D warnings
# package workflow musl + initramfs + SHA256SUMS + plan-only launcher
```

Guest 013 was **not** executed in CI.

## Related

- Crate: `zaquion-core/ryoku-hwprobe/`
- [ryoku-minimal.md](ryoku-minimal.md) · [console.md](console.md)
- Splash / First Pixels prep: [splash-prep-014.md](splash-prep-014.md)
- PR #7 · artifact tip `649b850`
