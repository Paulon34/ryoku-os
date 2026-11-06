# ryoku-virtlab

Ryoku **Virtual Lab** harness — **T0** (always) and **T1** (optional QEMU).

## Commands

```bash
cd zaquion-core
cargo test -p ryoku-virtlab
cargo run -p ryoku-virtlab -- t0
cargo run -p ryoku-virtlab -- t1
cargo run -p ryoku-virtlab -- all
```

Lab assets live in [`../../tests/qemu`](../../tests/qemu).

## Dependencies

**None** beyond the Rust standard library. Argv is always `Vec<String>` (no shell).

## License

Dual **MIT OR Apache-2.0** (workspace).
