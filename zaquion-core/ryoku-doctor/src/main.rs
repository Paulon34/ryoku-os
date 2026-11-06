//! `ryoku-doctor` CLI entrypoint.
//!
//! ```text
//! cargo run -p ryoku-doctor
//! ```

use std::env;
use std::process::ExitCode;

use ryoku_doctor::{Doctor, HostCommandRunner, HostFsProbe};

fn main() -> ExitCode {
    let mut args = env::args().skip(1);
    match args.next().as_deref() {
        None => run_doctor(),
        Some("-h") | Some("--help") => {
            print_help();
            ExitCode::SUCCESS
        }
        Some("-V") | Some("--version") => {
            println!("ryoku-doctor {}", env!("CARGO_PKG_VERSION"));
            ExitCode::SUCCESS
        }
        Some(other) => {
            eprintln!("error: unrecognized argument `{other}`");
            print_help();
            ExitCode::from(2)
        }
    }
}

fn run_doctor() -> ExitCode {
    let doctor = Doctor::new();
    let findings = doctor.diagnose(&HostCommandRunner, &HostFsProbe);
    print!("{}", Doctor::render_report(&findings));
    match Doctor::exit_code(&findings) {
        0 => ExitCode::SUCCESS,
        code => ExitCode::from(u8::try_from(code).unwrap_or(1)),
    }
}

fn print_help() {
    println!(
        "\
ryoku-doctor — read-only host diagnostics for Ryoku OS / Zaquion Core

USAGE:
    ryoku-doctor
    ryoku-doctor --help
    ryoku-doctor --version

BEHAVIOR:
    Reports OK / WARN / FAIL for required and optional developer tools.
    Never uses sudo, never installs packages, never changes permissions.
    Missing QEMU or inaccessible KVM is WARN (optional), not a Rust build failure.

BUILD:
    cd zaquion-core && cargo run -p ryoku-doctor
"
    );
}
