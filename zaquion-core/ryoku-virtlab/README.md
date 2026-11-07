# ryoku-virtlab

Ryoku **Virtual Lab** harness — **T0** (always), **T1** (optional QEMU),
**T2** first-boot (reference Alpine), **T3** boot-seed (opt-in).

## Commands

```bash
cd zaquion-core
cargo test -p ryoku-virtlab
cargo run -p ryoku-virtlab -- t0
cargo run -p ryoku-virtlab -- t1
cargo run -p ryoku-virtlab -- first-boot
cargo run -p ryoku-virtlab -- all          # T0+T1+T2 only
# cargo run -p ryoku-virtlab -- boot-seed  # T3 — needs kernel+initrd + auth
```

Lab assets live in [`../../tests/qemu`](../../tests/qemu).

See [docs/testing/boot-seed.md](../../docs/testing/boot-seed.md). Boot seed ≠ product boot.

## Dependencies

**None** beyond the Rust standard library. Argv is always `Vec<String>` (no shell).

## License

Dual **MIT OR Apache-2.0** (workspace).
