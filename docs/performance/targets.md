# Performance First — preliminary targets (Mission 002)

**Status:** goals only. **No measurements were taken in Mission 002** (no ISO, no VM boots, no benchmark runs).

Clear separation:

| Kind | Meaning |
|------|---------|
| **Goal** | Product intent to guide packaging and service design |
| **Measured** | Number produced by a documented benchmark on a named config — *none yet* |

## Distribution size

| Item | Goal | Measured |
|------|------|----------|
| Main / Full ISO | **≤ 3 GB**, prefer **2.0–2.5 GB** | *not measured* |
| Lite ISO / image | Smaller than Full; exact cap TBD after first squashfs pipeline | *not measured* |
| Server profile | Prefer headless; avoid Desktop/GPU stacks | *not measured* |

How we will measure later: compressed ISO byte size from a reproducible packaging job; publish the job id + commit SHA with the number.

## Memory (Lite)

| Item | Goal | Measured |
|------|------|----------|
| Lite usable on ~**2 GB RAM** hosts | Boot to a usable shell / minimal session without thrashing under a documented workload | *not measured* — **subject to tests** |
| Idle RAM after boot (Lite) | TBD once userland bootstrap is chosen | *not measured* |

“2 GB RAM” is a **design goal**, not a claim. Validate with QEMU `-m 2048` (and tighter) smokes in a future harness mission.

## CPU / boot

| Item | Goal | Measured |
|------|------|----------|
| Boot to multi-user (headless) | Track p50/p95 wall time under fixed QEMU flags | *not measured* |
| Cold vs warm boot | Separate metrics; document firmware/disk cache conditions | *not measured* |

## Storage

| Item | Goal | Measured |
|------|------|----------|
| Minimal installed root (Lite) | Prefer small base; optional features on demand | *not measured* |
| Writable overhead | Avoid unbounded log growth by default | *not measured* |

## Services & features

Principles (goals, not code yet):

1. **Minimize background services** on Lite/Server — nothing enabled “just in case”.
2. **Optional features on demand** — Gaming/Full profiles opt in; Desktop is not assumed on Lite/Server.
3. **Zaquion services** should be lean, start on demand when possible, and expose a clear disable path.
4. Prefer **measuring before adding** daemons that wake on timers.

## Reproducible benchmark plan (future)

Documented in more detail when the QEMU harness exists; outline:

1. **Fixed machine profile** — QEMU flags, vCPU count, RAM, disk backend (virtio), CPU model.
2. **Fixed image** — commit SHA + profile name (Lite/Full/…).
3. **Scripts** under `tests/` producing JSON: boot seconds, idle RSS, disk used, ISO bytes.
4. **CI** may run a subset on schedule; KVM not assumed on GitHub-hosted runners (TCG allowed but labeled slower).
5. Publish results as CI artifacts, not huge blobs in Git.

## Non-goals for Mission 002

- No benchmark numbers invented or implied as measured.
- No ISO size claims based on empty packaging placeholders.
- No tuning of host sysctl or guest kernels in this mission.

## Mission 016.1 / 016.2 note (Adaptive + Controlled Performance)

Shell-preview emits **compose/present** samples on the guest serial console.
Mission **016.2** adds an opt-in **controlled** harness (identical full/band
workload per profile; mean/p95). Those numbers (especially under QEMU **TCG**)
are **not** hardware measurements, are **instrumented** (`COST_INSTRUMENTED`),
and must not be published as product benchmarks. See
[`../testing/ryoku-adaptive-0162.md`](../testing/ryoku-adaptive-0162.md).

## Related docs

- [../testing/qemu-strategy.md](../testing/qemu-strategy.md)
- [../testing/ryoku-adaptive-0161.md](../testing/ryoku-adaptive-0161.md)
- [../testing/ryoku-adaptive-0162.md](../testing/ryoku-adaptive-0162.md)
- [../../packaging/profiles/](../../packaging/profiles/)
- [../../ROADMAP.md](../../ROADMAP.md)
