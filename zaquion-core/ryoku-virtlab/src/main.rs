//! `ryoku-virtlab` CLI — run T0 (always) and T1 (optional QEMU).

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use ryoku_virtlab::report::{exit_code, format_lab_report};
use ryoku_virtlab::{run_t0, run_t1, HostToolProbe};

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
        "t0" | "t1" | "all" => run_suite(args[0].as_str()),
        other => {
            eprintln!("error: unknown command `{other}`");
            print_help();
            ExitCode::from(2)
        }
    }
}

fn run_suite(which: &str) -> ExitCode {
    let lab_root = discover_lab_root();
    if let Err(err) = ensure_lab_dirs(&lab_root) {
        eprintln!("error: {err}");
        return ExitCode::from(1);
    }

    let probe = HostToolProbe;
    let mut results = Vec::new();
    if which == "t0" || which == "all" {
        results.extend(run_t0(&lab_root, &probe));
    }
    if which == "t1" || which == "all" {
        results.extend(run_t1(&lab_root, &probe));
    }

    let title = format!("Ryoku Virtual Lab ({which})");
    let report = format_lab_report(&title, &results);
    print!("{report}");

    let results_dir = lab_root.join("results");
    let _ = fs::create_dir_all(&results_dir);
    let out_path = results_dir.join(format!("{which}-latest.txt"));
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
    // Prefer cwd/tests/qemu, then relative to this crate's manifest via CARGO_MANIFEST_DIR.
    let candidates = [
        PathBuf::from("tests/qemu"),
        PathBuf::from("../tests/qemu"),
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../tests/qemu"),
    ];
    for path in candidates {
        if path.join("configs").exists() || path.join("fixtures").exists() {
            return path;
        }
    }
    PathBuf::from("tests/qemu")
}

fn ensure_lab_dirs(lab_root: &Path) -> Result<(), String> {
    for name in ["fixtures", "configs", "expectations", "run", "results"] {
        let dir = lab_root.join(name);
        fs::create_dir_all(&dir).map_err(|err| format!("{}: {err}", dir.display()))?;
        // Keep empty dirs representable in git via .gitkeep when we ship them.
    }
    Ok(())
}

fn print_help() {
    println!(
        "\
ryoku-virtlab — Ryoku Virtual Lab harness (T0/T1)

USAGE:
    ryoku-virtlab all
    ryoku-virtlab t0
    ryoku-virtlab t1
    ryoku-virtlab --help

NOTES:
    T0 always runs (config/security/argv/tool detection).
    T1 SKIPPED when QEMU is absent; OS boot is NOT_RUN without a guest image.
    Never attaches host physical disks; never uses sudo or package installs.
"
    );
}
