# Ryoku Virtual Lab (`tests/qemu`)

Safe QEMU harness assets for **T0** (always), **T1** (optional emulator),
**first-boot / T2** (reference Alpine ≠ Ryoku), and **boot-seed / T3**
(first-party `ryoku-init`; opt-in; ≠ product boot).

## Layout

```
tests/qemu/
├── configs/          # *.rvl.conf VM profiles (git) — t2 Alpine + t3 boot-seed
├── fixtures/         # small metadata only — NOT large ISOs/kernels
├── expectations/     # future serial sentinels (git)
├── scripts/          # fetch + boot-seed initramfs (dry-run by default)
├── run/              # disposable images/workdir (gitignored contents)
├── results/          # harness reports + evidence JSON (gitignored)
└── README.md
```

Harness binary: `zaquion-core` crate **`ryoku-virtlab`**.

```bash
cd zaquion-core
cargo test -p ryoku-virtlab
cargo run -p ryoku-virtlab -- t0
cargo run -p ryoku-virtlab -- first-boot
cargo run -p ryoku-virtlab -- all          # T0+T1+T2 only
# boot-seed/T3 is opt-in after kernel+initrd + separate authorization:
# cargo run -p ryoku-virtlab -- boot-seed
```

Reference Alpine fetch (default **dry-run**, no download):

```bash
tests/qemu/scripts/fetch-reference-image.sh
# Policy mocks (no network ISO): GPG fail-closed + redirect hop allowlist
tests/qemu/scripts/test-fetch-policy.sh
```

Authorized execute belongs on a **disposable** ubuntu-24.04 Actions runner (Mission 006), not the Cursor host.  
Downloads never use `curl -L`; every redirect hop must stay on the allowlisted HTTPS host. GPG verify is **fail-closed** (exit 0 + GOODSIG + VALIDSIG fingerprint).

See [docs/testing/reference-linux.md](../../docs/testing/reference-linux.md). **Reference Linux ≠ Ryoku OS.**

First-boot Alpine TCG **PASS** is a completed milestone (Mission 007.1). Boot Seed
docs: [boot-seed.md](../../docs/testing/boot-seed.md).

## Outcomes

| Status | Meaning |
|--------|---------|
| **PASS** | Case ran and met criteria (T2: Alpine serial markers; T3: `RYOKU_BOOT_SEED_READY`) |
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
