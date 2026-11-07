# Boot Seed T3 — preparation & evidence plan (Mission 009)

## Honesty

| Claim | Allowed when |
|-------|----------------|
| Prep scripts / unit tests / dry-runs | Always (no guest) |
| Workflow file present | Prep only — **do not dispatch** until authorized |
| `t3.boot_seed` PASS | Authorized disposable runner; **guest serial** has `ryoku-init: pid=1` **and** `RYOKU_BOOT_SEED_READY` |
| Ryoku OS product boot | **Never** from this seed alone |

Alpine virt ISO / `vmlinuz-virt` reuse is **lab kernel only** — not a definitive Ryoku base (ADR-0002).

## Reference kernel plan (Option A — T2 channel)

| Field | Value |
|-------|--------|
| ISO | `alpine-virt-3.21.9-x86_64.iso` |
| SHA-256 | `1ceafa2ca068faf2925de977815681c182708f3c6cbfbad137f3ffc9324a03b4` |
| GPG | ncopa `0482D84022F52DF1C4E7CD43293ACD0907D9495A` |
| Member | `boot/vmlinuz-virt` |
| Extract | `tests/qemu/scripts/extract-boot-seed-kernel.sh` (isoinfo/xorriso; **no** host disk mounts) |
| Output | `tests/qemu/run/ryoku-boot-seed-vmlinuz` (gitignored) |

Manifest: `tests/qemu/fixtures/boot-seed-kernel.manifest`.  
**Mission 009 does not download** the ISO on Cursor.

## ryoku-init + initramfs prep

1. Musl: `cargo build -p ryoku-init --release --target x86_64-unknown-linux-musl`
2. Static proof: `ryoku-virtlab check-static-elf` (ELF64 x86_64, exec `PT_LOAD`, no `PT_INTERP`/`DT_NEEDED`)
3. Pack: `/init` + `/dev/console` char **5:1** via `build-boot-seed-initramfs.sh`
4. Hashes: `prep-boot-seed-artifacts.sh` → `tests/qemu/results/boot-seed-artifact-hashes.txt`

Dry-run default on all scripts. `RYOKU_INITRAMFS_ALLOW_DYNAMIC=1` remains **blocked**.

## Harness guard

`ryoku-virtlab boot-seed` / `t3` **will not spawn QEMU** unless `RYOKU_T3_EXECUTE=1`.  
Without it → `t3.boot_seed` **NOT_RUN** even if kernel+initrd exist.  
`all` still runs only T0+T1+T2.

## Manual workflow (not dispatched in Mission 009)

File: `.github/workflows/boot-seed-t3.yml`

- `workflow_dispatch` only; `confirm=RUN` gate; `ref: main`
- Disposable `ubuntu-24.04`; `permissions: contents: read`
- Guest: TCG, `network=none`, no physical disks, job timeout
- Sets `RYOKU_T3_EXECUTE=1` only inside that job

## Evidence checklist (authorized T3 run)

| Artifact | Purpose |
|----------|---------|
| ISO SHA-256 + GPG sidecars | Provenance of Alpine ISO (T2 channel) |
| `boot-seed-kernel.sha256` | Extracted `vmlinuz-virt` integrity |
| `boot-seed-artifact-hashes.txt` | musl `/init` + initramfs digests |
| Initramfs metadata | `./init` executable + `./dev/console` 5:1 |
| QEMU argv | `-accel tcg`, `-nic none`, `-kernel`, `-initrd`, no `/dev/sd*` |
| Guest serial log | Must contain both required markers |
| `boot-seed-evidence.json` | `"verdict": "PASS"` only from **serial** |
| Product case | `t3.ryoku_os_product_boot` stays **NOT_RUN** |

PASS eligibility is **serial-only** — never QEMU stdout/stderr alone.

## What Mission 009 does / does not

| Does | Does not |
|------|----------|
| Document kernel reuse + extract script | Download ISO/kernel on Cursor |
| Dry-run prep + policy tests | Run T3 guest |
| Add gated workflow file | `workflow_dispatch` / claim PASS |
| Harness `RYOKU_T3_EXECUTE` guard | Merge/push/PR (local branch only) |
