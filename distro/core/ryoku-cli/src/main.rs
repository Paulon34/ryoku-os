//! `ryoku` CLI — Debian track operator tool (ENTREGA D).
//!
//! Subcommands: config | profile | system-info | jarvis-bridge

use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::ExitCode;

use ryoku_jarvis_bridge::{self as jarvis, marker_path};

fn main() -> ExitCode {
    let mut args = env::args().skip(1);
    match args.next().as_deref() {
        None | Some("-h") | Some("--help") => {
            print_help();
            ExitCode::SUCCESS
        }
        Some("-V") | Some("--version") => {
            println!("ryoku {}", env!("CARGO_PKG_VERSION"));
            ExitCode::SUCCESS
        }
        Some("config") => cmd_config(args.collect()),
        Some("profile") => cmd_profile(args.collect()),
        Some("system-info") => cmd_system_info(),
        Some("jarvis-bridge") => cmd_jarvis(args.collect()),
        Some(other) => {
            eprintln!("error: unknown subcommand `{other}`");
            print_help();
            ExitCode::from(2)
        }
    }
}

fn print_help() {
    println!(
        "\
ryoku — Ryoku Debian operator CLI

USAGE:
  ryoku <subcommand>

SUBCOMMANDS:
  config          Show Ryoku config paths / overlay hints
  profile         Show active profile.json (edition/visual/jarvis)
  system-info     Host/OS summary (read-only)
  jarvis-bridge   status | enable | disable   (off by default)

OPTIONS:
  -h, --help      Show help
  -V, --version   Show version
"
    );
}

fn xdg_config_home() -> PathBuf {
    env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            let home = env::var_os("HOME").unwrap_or_else(|| ".".into());
            PathBuf::from(home).join(".config")
        })
}

fn cmd_config(args: Vec<String>) -> ExitCode {
    if args.iter().any(|a| a == "-h" || a == "--help") {
        println!("ryoku config — print config locations");
        return ExitCode::SUCCESS;
    }
    let cfg = xdg_config_home();
    println!("config_home: {}", cfg.display());
    println!("ryoku_dir:   {}", cfg.join("ryoku").display());
    println!(
        "profile:     {}",
        cfg.join("ryoku").join("profile.json").display()
    );
    println!(
        "settings:    {}",
        cfg.join("ryoku").join("settings.json").display()
    );
    println!("jarvis_marker: {}", marker_path().display());
    println!("overlay_hint: distro/flake/.ryoku-user.nix (bootstrap local)");
    ExitCode::SUCCESS
}

fn cmd_profile(args: Vec<String>) -> ExitCode {
    if args.iter().any(|a| a == "-h" || a == "--help") {
        println!("ryoku profile — show ~/.config/ryoku/profile.json");
        return ExitCode::SUCCESS;
    }
    let path = xdg_config_home().join("ryoku").join("profile.json");
    match fs::read_to_string(&path) {
        Ok(text) => {
            print!("{text}");
            if !text.ends_with('\n') {
                println!();
            }
            if let Some(flag) = jarvis::profile_jarvis_flag(&xdg_config_home()) {
                println!("jarvis_in_profile: {flag}");
            }
            ExitCode::SUCCESS
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            eprintln!("profile not found: {}", path.display());
            eprintln!("hint: run bootstrap --apply or set ryoku.profile.* in HM");
            ExitCode::from(1)
        }
        Err(e) => {
            eprintln!("error reading {}: {e}", path.display());
            ExitCode::from(1)
        }
    }
}

fn cmd_system_info() -> ExitCode {
    println!("ryoku-cli {}", env!("CARGO_PKG_VERSION"));
    if let Ok(os) = fs::read_to_string("/etc/os-release") {
        for line in os.lines() {
            if line.starts_with("PRETTY_NAME=")
                || line.starts_with("VERSION_ID=")
                || line.starts_with("VERSION_CODENAME=")
                || line.starts_with("ID=")
            {
                println!("{line}");
            }
        }
    } else {
        println!("os-release: unavailable");
    }
    println!("arch: {}", env::consts::ARCH);
    println!("nixos: {}", PathBuf::from("/etc/NIXOS").exists());
    println!("jarvis_enabled: {}", jarvis::is_enabled());
    println!("guest_claim: GUEST_NOT_RUN  # CLI does not invent PASS_MANUAL");
    ExitCode::SUCCESS
}

fn cmd_jarvis(args: Vec<String>) -> ExitCode {
    let sub = args.first().map(String::as_str).unwrap_or("status");
    match sub {
        "-h" | "--help" => {
            println!("ryoku jarvis-bridge [status|enable|disable]");
            ExitCode::SUCCESS
        }
        "status" => {
            println!("{}", jarvis::status_report());
            ExitCode::SUCCESS
        }
        "enable" => match jarvis::enable() {
            Ok(()) => {
                println!("jarvis: enabled ({})", marker_path().display());
                ExitCode::SUCCESS
            }
            Err(e) => {
                eprintln!("error: {e}");
                ExitCode::from(1)
            }
        },
        "disable" => match jarvis::disable() {
            Ok(()) => {
                println!("jarvis: disabled");
                ExitCode::SUCCESS
            }
            Err(e) => {
                eprintln!("error: {e}");
                ExitCode::from(1)
            }
        },
        other => {
            eprintln!("error: unknown jarvis-bridge action `{other}`");
            ExitCode::from(2)
        }
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn jarvis_status_non_empty() {
        let report = ryoku_jarvis_bridge::status_report();
        assert!(report.contains("jarvis:"));
    }
}
