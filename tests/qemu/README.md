# Ryoku Virtual Lab (`tests/qemu`)

Safe QEMU harness assets for **T0** (always) and **T1** (optional emulator).

## Layout

```
tests/qemu/
├── configs/          # *.rvl.conf VM profiles (git)
├── fixtures/         # small metadata only — NOT large ISOs
├── expectations/     # future serial sentinels (git)
├── run/              # disposable images/workdir (gitignored contents)
├── results/          # harness reports (gitignored contents)
└── README.md
```

Harness binary: `zaquion-core` crate **`ryoku-virtlab`**.

```bash
cd zaquion-core
cargo test -p ryoku-virtlab
cargo run -p ryoku-virtlab -- t0
cargo run -p ryoku-virtlab -- all
```

## Outcomes

| Status | Meaning |
|--------|---------|
| **PASS** | Case ran and met criteria |
| **FAIL** | Case ran and failed (or required validation failed) |
| **SKIPPED** | Intentionally not executed (e.g. QEMU missing for T1) |
| **NOT_RUN** | Stronger claim not attempted (e.g. OS boot without guest image) |

## Safety

- No sudo, no package installs, no KVM permission changes
- No `/dev/sd*`, `/dev/nvme*`, or other host block devices
- No default host networking (`network = none`)
- No third-party ISO downloads in Mission 003
- Never claim Ryoku OS booted without a bootable kernel/system under test

See [docs/testing/virtual-lab.md](../../docs/testing/virtual-lab.md).
