//! `ryoku-virtlab` CLI — T0 / T1 / first-boot / boot-seed / ELF+initramfs helpers.

use std::env;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use ryoku_virtlab::elf_static::prove_static_x86_64_elf;
use ryoku_virtlab::initramfs::{
    pack_boot_seed_from_init_path, pack_ryoku_graphics_from_paths_with_modules,
    pack_ryoku_minimal_from_paths, validate_boot_seed_cpio, validate_ryoku_minimal_cpio,
    RYOKU_GRAPHICS_RELEASE_TEXT, RYOKU_RELEASE_TEXT,
};
use ryoku_virtlab::lab::discover_lab_root_from;
use ryoku_virtlab::report::{exit_code, format_lab_report};
use ryoku_virtlab::{run_boot_seed, run_first_boot, run_t0, run_t1, HostToolProbe};

fn main() -> ExitCode {
    let mut args = env::args().skip(1).collect::<Vec<_>>();
    if args.is_empty() {
        args.push("all".into());
    }

    match args[0].as_str() {
        "-h" | "--help" => {
            print_help();
            ExitCode::SUCCESS
        }
        "-V" | "--version" => {
            println!("ryoku-virtlab {}", env!("CARGO_PKG_VERSION"));
            ExitCode::SUCCESS
        }
        "t0" | "t1" | "first-boot" | "t2" | "boot-seed" | "t3" | "all" => {
            run_suite(args[0].as_str())
        }
        "print-lab-paths" => print_lab_paths(),
        "check-static-elf" => {
            if args.len() != 2 {
                eprintln!("usage: ryoku-virtlab check-static-elf <path>");
                return ExitCode::from(2);
            }
            match prove_static_x86_64_elf(Path::new(&args[1])) {
                Ok(()) => {
                    println!(
                        "OK: proven static x86_64 ELF (no PT_INTERP, no DT_NEEDED): {}",
                        args[1]
                    );
                    ExitCode::SUCCESS
                }
                Err(err) => {
                    eprintln!("REFUSE: {}", err);
                    ExitCode::from(1)
                }
            }
        }
        "pack-boot-seed-cpio" => {
            // Writes uncompressed newc to stdout or --out path. Caller may gzip.
            // usage: pack-boot-seed-cpio --init <bin> --out <file.cpio>
            let mut init: Option<PathBuf> = None;
            let mut out: Option<PathBuf> = None;
            let mut i = 1;
            while i < args.len() {
                match args[i].as_str() {
                    "--init" => {
                        i += 1;
                        init = args.get(i).map(PathBuf::from);
                    }
                    "--out" => {
                        i += 1;
                        out = args.get(i).map(PathBuf::from);
                    }
                    other => {
                        eprintln!("error: unknown arg `{other}`");
                        return ExitCode::from(2);
                    }
                }
                i += 1;
            }
            let Some(init) = init else {
                eprintln!(
                    "usage: ryoku-virtlab pack-boot-seed-cpio --init <bin> --out <file.cpio>"
                );
                return ExitCode::from(2);
            };
            let Some(out) = out else {
                eprintln!(
                    "usage: ryoku-virtlab pack-boot-seed-cpio --init <bin> --out <file.cpio>"
                );
                return ExitCode::from(2);
            };
            // Static proof required before packing for guest prep.
            if let Err(err) = prove_static_x86_64_elf(&init) {
                eprintln!("REFUSE pack: init not proven static x86_64: {err}");
                return ExitCode::from(1);
            }
            match pack_boot_seed_from_init_path(&init) {
                Ok(bytes) => {
                    if let Err(err) = validate_boot_seed_cpio(&bytes) {
                        eprintln!("REFUSE pack: validation failed: {err}");
                        return ExitCode::from(1);
                    }
                    if let Some(parent) = out.parent() {
                        let _ = fs::create_dir_all(parent);
                    }
                    match fs::File::create(&out).and_then(|mut f| f.write_all(&bytes)) {
                        Ok(()) => {
                            println!("OK: wrote {} ({} bytes newc)", out.display(), bytes.len());
                            ExitCode::SUCCESS
                        }
                        Err(err) => {
                            eprintln!("error writing {}: {err}", out.display());
                            ExitCode::from(1)
                        }
                    }
                }
                Err(err) => {
                    eprintln!("error: {err}");
                    ExitCode::from(1)
                }
            }
        }
        "pack-ryoku-graphics-cpio" => {
            // Mission 014/014.1 — Minimal + graphics-demo (+ optional DRM modules).
            // Does not replace serial Minimal package.
            let mut init: Option<PathBuf> = None;
            let mut console: Option<PathBuf> = None;
            let mut demo: Option<PathBuf> = None;
            let mut modules: Option<PathBuf> = None;
            let mut out: Option<PathBuf> = None;
            let mut i = 1;
            while i < args.len() {
                match args[i].as_str() {
                    "--init" => {
                        i += 1;
                        init = args.get(i).map(PathBuf::from);
                    }
                    "--console" => {
                        i += 1;
                        console = args.get(i).map(PathBuf::from);
                    }
                    "--graphics-demo" => {
                        i += 1;
                        demo = args.get(i).map(PathBuf::from);
                    }
                    "--modules-dir" => {
                        i += 1;
                        modules = args.get(i).map(PathBuf::from);
                    }
                    "--out" => {
                        i += 1;
                        out = args.get(i).map(PathBuf::from);
                    }
                    other => {
                        eprintln!("error: unknown arg `{other}`");
                        return ExitCode::from(2);
                    }
                }
                i += 1;
            }
            let (Some(init), Some(console), Some(demo), Some(out)) = (init, console, demo, out)
            else {
                eprintln!(
                    "usage: ryoku-virtlab pack-ryoku-graphics-cpio --init <bin> --console <bin> \
                     --graphics-demo <bin> [--modules-dir <staged>] --out <file.cpio>"
                );
                return ExitCode::from(2);
            };
            for (label, path) in [
                ("init", &init),
                ("console", &console),
                ("graphics-demo", &demo),
            ] {
                if let Err(err) = prove_static_x86_64_elf(path) {
                    eprintln!("REFUSE pack: {label} not proven static x86_64: {err}");
                    return ExitCode::from(1);
                }
            }
            match pack_ryoku_graphics_from_paths_with_modules(
                &init,
                &console,
                &demo,
                RYOKU_GRAPHICS_RELEASE_TEXT,
                modules.as_deref(),
            ) {
                Ok(bytes) => match fs::File::create(&out).and_then(|mut f| f.write_all(&bytes)) {
                    Ok(()) => {
                        println!(
                            "OK: wrote {} ({} bytes newc graphics preview{})",
                            out.display(),
                            bytes.len(),
                            if modules.is_some() {
                                " + DRM modules"
                            } else {
                                ""
                            }
                        );
                        ExitCode::SUCCESS
                    }
                    Err(err) => {
                        eprintln!("error writing {}: {err}", out.display());
                        ExitCode::from(1)
                    }
                },
                Err(err) => {
                    eprintln!("error: {err}");
                    ExitCode::from(1)
                }
            }
        }
        "pack-ryoku-minimal-cpio" => {
            // Mission 012 — Minimal initramfs with console (separate from T3 boot-seed).
            // usage: pack-ryoku-minimal-cpio --init <bin> --console <bin> --out <file.cpio>
            let mut init: Option<PathBuf> = None;
            let mut console: Option<PathBuf> = None;
            let mut out: Option<PathBuf> = None;
            let mut i = 1;
            while i < args.len() {
                match args[i].as_str() {
                    "--init" => {
                        i += 1;
                        init = args.get(i).map(PathBuf::from);
                    }
                    "--console" => {
                        i += 1;
                        console = args.get(i).map(PathBuf::from);
                    }
                    "--out" => {
                        i += 1;
                        out = args.get(i).map(PathBuf::from);
                    }
                    other => {
                        eprintln!("error: unknown arg `{other}`");
                        return ExitCode::from(2);
                    }
                }
                i += 1;
            }
            let (Some(init), Some(console), Some(out)) = (init, console, out) else {
                eprintln!(
                    "usage: ryoku-virtlab pack-ryoku-minimal-cpio --init <bin> --console <bin> --out <file.cpio>"
                );
                return ExitCode::from(2);
            };
            if let Err(err) = prove_static_x86_64_elf(&init) {
                eprintln!("REFUSE pack: init not proven static x86_64: {err}");
                return ExitCode::from(1);
            }
            if let Err(err) = prove_static_x86_64_elf(&console) {
                eprintln!("REFUSE pack: console not proven static x86_64: {err}");
                return ExitCode::from(1);
            }
            match pack_ryoku_minimal_from_paths(&init, &console, RYOKU_RELEASE_TEXT) {
                Ok(bytes) => {
                    if let Err(err) = validate_ryoku_minimal_cpio(&bytes) {
                        eprintln!("REFUSE pack: validation failed: {err}");
                        return ExitCode::from(1);
                    }
                    if let Some(parent) = out.parent() {
                        let _ = fs::create_dir_all(parent);
                    }
                    match fs::File::create(&out).and_then(|mut f| f.write_all(&bytes)) {
                        Ok(()) => {
                            println!(
                                "OK: wrote Minimal {} ({} bytes newc)",
                                out.display(),
                                bytes.len()
                            );
                            ExitCode::SUCCESS
                        }
                        Err(err) => {
                            eprintln!("error writing {}: {err}", out.display());
                            ExitCode::from(1)
                        }
                    }
                }
                Err(err) => {
                    eprintln!("error: {err}");
                    ExitCode::from(1)
                }
            }
        }
        other => {
            eprintln!("error: unknown command `{other}`");
            print_help();
            ExitCode::from(2)
        }
    }
}

fn run_suite(which: &str) -> ExitCode {
    let lab_root = discover_lab_root();
    eprintln!("lab_root_abs={}", lab_root.display());
    if let Err(err) = ensure_lab_dirs(&lab_root) {
        eprintln!("error: {err}");
        return ExitCode::from(1);
    }

    let probe = HostToolProbe;
    let mut results = Vec::new();
    let label = match which {
        "t2" => "first-boot",
        "t3" => "boot-seed",
        other => other,
    };

    if which == "t0" || which == "all" {
        results.extend(run_t0(&lab_root, &probe));
    }
    if which == "t1" || which == "all" {
        results.extend(run_t1(&lab_root, &probe));
    }
    if which == "first-boot" || which == "t2" || which == "all" {
        results.extend(run_first_boot(&lab_root, &probe));
    }
    if which == "boot-seed" || which == "t3" {
        results.extend(run_boot_seed(&lab_root, &probe));
    }

    let title = format!("Ryoku Virtual Lab ({label})");
    let report = format_lab_report(&title, &results);
    print!("{report}");

    let results_dir = lab_root.join("results");
    let _ = fs::create_dir_all(&results_dir);
    let out_path = results_dir.join(format!("{label}-latest.txt"));
    if let Err(err) = fs::write(&out_path, &report) {
        eprintln!("warning: could not write {}: {err}", out_path.display());
    } else {
        eprintln!("wrote {}", out_path.display());
    }

    match exit_code(&results) {
        0 => ExitCode::SUCCESS,
        code => ExitCode::from(u8::try_from(code).unwrap_or(1)),
    }
}

fn discover_lab_root() -> PathBuf {
    let cwd = env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    discover_lab_root_from(&cwd, Path::new(env!("CARGO_MANIFEST_DIR")))
}

fn print_lab_paths() -> ExitCode {
    let lab_root = discover_lab_root();
    let iso = lab_root.join("run/alpine-virt-3.21.9-x86_64.iso");
    let sha = lab_root.join("run/alpine-virt-3.21.9-x86_64.iso.sha256");
    let asc = lab_root.join("run/alpine-virt-3.21.9-x86_64.iso.asc");
    let kernel = lab_root.join("run/ryoku-boot-seed-vmlinuz");
    let initrd = lab_root.join("run/ryoku-boot-seed.cpio.gz");
    let minimal = lab_root.join("run/ryoku-minimal.cpio.gz");
    println!("lab_root_abs={}", lab_root.display());
    println!("iso_abs={}", iso.display());
    println!("iso_exists={}", iso.is_file());
    println!("sha256_sidecar_exists={}", sha.is_file());
    println!("asc_sidecar_exists={}", asc.is_file());
    println!("boot_seed_kernel_abs={}", kernel.display());
    println!("boot_seed_kernel_exists={}", kernel.is_file());
    println!("boot_seed_initrd_abs={}", initrd.display());
    println!("boot_seed_initrd_exists={}", initrd.is_file());
    println!("ryoku_minimal_initrd_abs={}", minimal.display());
    println!("ryoku_minimal_initrd_exists={}", minimal.is_file());
    if sha.is_file() && !iso.is_file() {
        eprintln!(
            "error: path inconsistency — checksum sidecar present but ISO missing at harness path"
        );
        return ExitCode::from(1);
    }
    ExitCode::SUCCESS
}

fn ensure_lab_dirs(lab_root: &Path) -> Result<(), String> {
    for name in [
        "fixtures",
        "configs",
        "expectations",
        "run",
        "results",
        "scripts",
    ] {
        let dir = lab_root.join(name);
        fs::create_dir_all(&dir).map_err(|err| format!("{}: {err}", dir.display()))?;
    }
    Ok(())
}

fn print_help() {
    println!(
        "\
ryoku-virtlab — Ryoku Virtual Lab harness (T0/T1/first-boot/boot-seed)

USAGE:
    ryoku-virtlab all
    ryoku-virtlab t0
    ryoku-virtlab t1
    ryoku-virtlab first-boot
    ryoku-virtlab boot-seed
    ryoku-virtlab print-lab-paths
    ryoku-virtlab check-static-elf <path>
    ryoku-virtlab pack-boot-seed-cpio --init <bin> --out <file.cpio>
    ryoku-virtlab pack-ryoku-minimal-cpio --init <bin> --console <bin> --out <file.cpio>
    ryoku-virtlab --help

NOTES:
    T0 always runs without QEMU.
    T1 / first-boot SKIPPED or NOT_RUN when QEMU or the reference ISO is absent.
    `all` runs T0+T1+T2 only — boot-seed/T3 is opt-in (separate authorization).
    Reference Linux boot is NEVER reported as Ryoku OS boot.
    Boot seed PASS requires guest serial `ryoku-init: pid=1` AND `RYOKU_BOOT_SEED_READY`.
    Ryoku Minimal (`pack-ryoku-minimal-cpio`) is separate from T3 file-serial evidence.
    Never attaches host physical disks; never uses sudo or package installs.
"
    );
}
