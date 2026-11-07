//! `ryoku-virtlab` CLI — T0 / T1 / first-boot / boot-seed.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

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

    // `all` keeps historical T0+T1+T2 only — T3 is opt-in until authorized.
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
    println!("lab_root_abs={}", lab_root.display());
    println!("iso_abs={}", iso.display());
    println!("iso_exists={}", iso.is_file());
    println!("sha256_sidecar_exists={}", sha.is_file());
    println!("asc_sidecar_exists={}", asc.is_file());
    println!("boot_seed_kernel_abs={}", kernel.display());
    println!("boot_seed_kernel_exists={}", kernel.is_file());
    println!("boot_seed_initrd_abs={}", initrd.display());
    println!("boot_seed_initrd_exists={}", initrd.is_file());
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
    ryoku-virtlab --help

NOTES:
    T0 always runs without QEMU.
    T1 / first-boot SKIPPED or NOT_RUN when QEMU or the reference ISO is absent.
    `all` runs T0+T1+T2 only — boot-seed/T3 is opt-in (separate authorization).
    Reference Linux boot is NEVER reported as Ryoku OS boot.
    Boot seed marker PASS ≠ finished Ryoku OS product boot.
    Never attaches host physical disks; never uses sudo or package installs.
"
    );
}
