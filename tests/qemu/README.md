# Ryoku Virtual Lab (`tests/qemu`)

Safe QEMU harness assets for **T0** (always), **T1** (optional emulator), and **first-boot / T2** (reference Alpine ≠ Ryoku).

## Layout

```
tests/qemu/
├── configs/          # *.rvl.conf VM profiles (git)
├── fixtures/         # small metadata only — NOT large ISOs
├── expectations/     # future serial sentinels (git)
├── scripts/          # fetch-reference-image.sh (dry-run by default)
├── run/              # disposable images/workdir (gitignored contents)
├── results/          # harness reports + verified-boot-evidence.json (gitignored)
└── README.md
```

Harness binary: `zaquion-core` crate **`ryoku-virtlab`**.

```bash
cd zaquion-core
cargo test -p ryoku-virtlab
cargo run -p ryoku-virtlab -- t0
cargo run -p ryoku-virtlab -- first-boot
cargo run -p ryoku-virtlab -- all
```

Reference Alpine fetch (default **dry-run**, no download):

```bash
tests/qemu/scripts/fetch-reference-image.sh
```

Authorized execute belongs on a **disposable** ubuntu-24.04 Actions runner (Mission 006), not the Cursor host.

See [docs/testing/reference-linux.md](../../docs/testing/reference-linux.md). **Reference Linux ≠ Ryoku OS.**

## Outcomes

| Status | Meaning |
|--------|---------|
| **PASS** | Case ran and met criteria (for T2: all Alpine serial markers present) |
| **FAIL** | Case ran and failed (or required validation failed) |
| **SKIPPED** | Intentionally not executed (e.g. QEMU missing for T1) |
| **NOT_RUN** | Stronger claim not attempted (e.g. OS boot without guest image) |

## Safety

- No sudo / package installs / KVM permission changes from local harness tooling
- No `/dev/sd*`, `/dev/nvme*`, or other host block devices
- No default host networking (`network = none`)
- ISO download only after authorization; never commit ISO bytes
- Never claim Ryoku OS booted without a bootable kernel/system under test

See [docs/testing/virtual-lab.md](../../docs/testing/virtual-lab.md).
