//! Individual diagnostic checks.

use std::env;
use std::path::Path;

use crate::finding::{Finding, Importance, Severity};
use crate::probe::{parse_os_release_pretty_name, FsProbe};
use crate::runner::CommandRunner;

const KVM_PATH: &str = "/dev/kvm";
const OS_RELEASE_PATH: &str = "/etc/os-release";

/// Run the full Mission 002 check suite against injected probes.
pub fn run_all_checks<R: CommandRunner, F: FsProbe>(runner: &R, fs: &F) -> Vec<Finding> {
    vec![
        check_os_arch(fs),
        check_tool(
            runner,
            "git",
            "git",
            &["--version"],
            Importance::Optional,
            "Git",
            "Useful for contributing; not required to compile Zaquion crates.",
        ),
        check_tool(
            runner,
            "rustc",
            "rustc",
            &["--version"],
            Importance::Required,
            "Rust compiler (rustc)",
            "Required to build Zaquion Core.",
        ),
        check_tool(
            runner,
            "cargo",
            "cargo",
            &["--version"],
            Importance::Required,
            "Cargo",
            "Required to build and test the workspace.",
        ),
        check_tool(
            runner,
            "rustfmt",
            "rustfmt",
            &["--version"],
            Importance::Optional,
            "rustfmt",
            "Optional locally; CI enforces `cargo fmt --check`.",
        ),
        check_clippy(runner),
        check_clang(runner),
        check_llvm_config(runner),
        check_qemu(runner),
        check_kvm(fs),
        check_make(runner),
    ]
}

fn check_os_arch<F: FsProbe>(fs: &F) -> Finding {
    let arch = env::consts::ARCH;
    let family = env::consts::OS;
    let pretty = fs
        .read_to_string(Path::new(OS_RELEASE_PATH))
        .ok()
        .and_then(|s| parse_os_release_pretty_name(&s));

    let summary = match &pretty {
        Some(name) => format!("{name}; OS family `{family}`; arch `{arch}`"),
        None => format!("OS family `{family}`; arch `{arch}` (no /etc/os-release PRETTY_NAME)"),
    };

    // Ryoku targets Linux hosts for OS development. Non-Linux is a WARN: the
    // doctor itself may still build, but kernel/QEMU workflows will not match.
    let (severity, detail) = if family == "linux" {
        (
            Severity::Ok,
            Some("Linux detected — expected for Ryoku OS host work.".to_string()),
        )
    } else {
        (
            Severity::Warn,
            Some(
                "Non-Linux host: you can still develop Rust crates, but QEMU/KVM and \
                 packaging workflows assume Linux."
                    .to_string(),
            ),
        )
    };

    let mut finding = Finding::new(
        "os-arch",
        "Operating system / architecture",
        severity,
        Importance::Required,
        summary,
    );
    if let Some(detail) = detail {
        finding = finding.with_detail(detail);
    }
    finding
}

fn check_tool(
    runner: &impl CommandRunner,
    id: &'static str,
    program: &str,
    args: &[&str],
    importance: Importance,
    title: &'static str,
    missing_hint: &str,
) -> Finding {
    let output = runner.run(program, args);
    classify_version_tool(id, title, importance, program, &output, missing_hint)
}

fn classify_version_tool(
    id: &'static str,
    title: &'static str,
    importance: Importance,
    program: &str,
    output: &crate::runner::CommandOutput,
    missing_hint: &str,
) -> Finding {
    if let Some(err) = &output.spawn_error {
        let severity = match importance {
            Importance::Required => Severity::Fail,
            Importance::Optional => Severity::Warn,
        };
        return Finding::new(
            id,
            title,
            severity,
            importance,
            format!("`{program}` not usable"),
        )
        .with_detail(format!("{err}. {missing_hint}"));
    }

    if !output.success() {
        let code = output
            .status_code
            .map(|c| c.to_string())
            .unwrap_or_else(|| "unknown".to_string());
        let severity = match importance {
            Importance::Required => Severity::Fail,
            Importance::Optional => Severity::Warn,
        };
        let mut stderr = output.stderr.trim().to_string();
        if stderr.is_empty() {
            stderr = output.stdout.trim().to_string();
        }
        if stderr.len() > 240 {
            stderr.truncate(240);
            stderr.push('…');
        }
        return Finding::new(
            id,
            title,
            severity,
            importance,
            format!("`{program}` exited with status {code}"),
        )
        .with_detail(if stderr.is_empty() {
            missing_hint.to_string()
        } else {
            format!("{stderr} — {missing_hint}")
        });
    }

    let version = output
        .first_line()
        .unwrap_or("(empty version output)")
        .to_string();

    // Unexpected empty success is a WARN so flaky tools surface without
    // hard-failing the whole required set unless importance demands it.
    if output.first_line().is_none() {
        return Finding::new(
            id,
            title,
            Severity::Warn,
            importance,
            format!("`{program}` returned success with empty output"),
        )
        .with_detail("Treating as WARN; verify the tool manually.".to_string());
    }

    Finding::new(id, title, Severity::Ok, importance, version)
}

fn check_clippy(runner: &impl CommandRunner) -> Finding {
    // `cargo clippy --version` works when the clippy component is installed.
    let output = runner.run("cargo", &["clippy", "--version"]);
    classify_version_tool(
        "clippy",
        "Clippy",
        Importance::Optional,
        "cargo clippy",
        &output,
        "Optional locally; CI runs clippy when the component is available.",
    )
}

fn check_clang(runner: &impl CommandRunner) -> Finding {
    let output = runner.run("clang", &["--version"]);
    classify_version_tool(
        "clang",
        "Clang",
        Importance::Optional,
        "clang",
        &output,
        "Optional for now; useful later for bindgen / kernel-adjacent tooling.",
    )
}

fn check_llvm_config(runner: &impl CommandRunner) -> Finding {
    let output = runner.run("llvm-config", &["--version"]);
    if output.success() {
        return classify_version_tool(
            "llvm-config",
            "LLVM (llvm-config)",
            Importance::Optional,
            "llvm-config",
            &output,
            "Optional.",
        );
    }
    // Many distros put llvm-config under /usr/lib/llvm-*/bin without PATH.
    // We only *report* that — we do not modify PATH or install packages.
    Finding::new(
        "llvm-config",
        "LLVM (llvm-config)",
        Severity::Warn,
        Importance::Optional,
        "`llvm-config` not on PATH",
    )
    .with_detail(
        "Optional. Clang may still work. Distros often ship `llvm-config` under \
         /usr/lib/llvm-*/bin; the doctor does not alter PATH or install packages."
            .to_string(),
    )
}

fn check_qemu(runner: &impl CommandRunner) -> Finding {
    // Prefer the system emulator used by the documented QEMU strategy.
    let output = runner.run("qemu-system-x86_64", &["--version"]);
    if output.spawn_error.is_none() {
        // Binary was spawnable — classify success or unexpected non-zero exit.
        return classify_version_tool(
            "qemu",
            "QEMU (qemu-system-x86_64)",
            Importance::Optional,
            "qemu-system-x86_64",
            &output,
            "Optional until the QEMU harness mission. Missing QEMU must not fail Rust builds.",
        );
    }

    // Fall back to qemu-img as a weaker signal that *some* QEMU userland exists.
    let img = runner.run("qemu-img", &["--version"]);
    if img.success() {
        return Finding::new(
            "qemu",
            "QEMU (qemu-system-x86_64)",
            Severity::Warn,
            Importance::Optional,
            "`qemu-system-x86_64` missing; `qemu-img` is present",
        )
        .with_detail(
            "Install the system emulator package before harness work. \
             Rust compilation does not require QEMU."
                .to_string(),
        );
    }

    Finding::new(
        "qemu",
        "QEMU (qemu-system-x86_64)",
        Severity::Warn,
        Importance::Optional,
        "QEMU not installed (or not on PATH)",
    )
    .with_detail(
        "Optional for Mission 002. Documented in docs/testing/qemu-strategy.md. \
         Missing QEMU is WARN/optional — it must not fail `cargo build` / `cargo test`."
            .to_string(),
    )
}

fn check_kvm<F: FsProbe>(fs: &F) -> Finding {
    let path = Path::new(KVM_PATH);
    if !fs.exists(path) {
        return Finding::new(
            "kvm",
            "KVM device (/dev/kvm)",
            Severity::Warn,
            Importance::Optional,
            "`/dev/kvm` not present",
        )
        .with_detail(
            "Optional until VM harness work. CI runners often lack KVM; that is expected. \
             The doctor never changes group membership or device permissions."
                .to_string(),
        );
    }

    let readable = fs.readable(path);
    let writable = fs.writable(path);
    if readable && writable {
        return Finding::new(
            "kvm",
            "KVM device (/dev/kvm)",
            Severity::Ok,
            Importance::Optional,
            "`/dev/kvm` exists and is read/write for this user",
        )
        .with_detail(
            "Hardware acceleration should be available to QEMU when QEMU is installed.".to_string(),
        );
    }

    Finding::new(
        "kvm",
        "KVM device (/dev/kvm)",
        Severity::Warn,
        Importance::Optional,
        format!("`/dev/kvm` exists but access is limited (read={readable}, write={writable})"),
    )
    .with_detail(
        "Do not chmod or usermod as part of Ryoku tooling missions. Record the limitation; \
         fix host policy outside the repo when a QEMU mission requires it."
            .to_string(),
    )
}

fn check_make(runner: &impl CommandRunner) -> Finding {
    check_tool(
        runner,
        "make",
        "make",
        &["--version"],
        Importance::Optional,
        "GNU Make",
        "Optional convenience for future packaging scripts.",
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::probe::MockFs;
    use crate::runner::{CommandOutput, MockRunner};
    use crate::Severity;

    fn healthy_runner() -> MockRunner {
        MockRunner::new()
            .with(
                "git",
                &["--version"],
                CommandOutput::ok("git version 2.43.0\n"),
            )
            .with("rustc", &["--version"], CommandOutput::ok("rustc 1.83.0\n"))
            .with("cargo", &["--version"], CommandOutput::ok("cargo 1.83.0\n"))
            .with(
                "rustfmt",
                &["--version"],
                CommandOutput::ok("rustfmt 1.8.0-stable\n"),
            )
            .with(
                "cargo",
                &["clippy", "--version"],
                CommandOutput::ok("clippy 0.1.83\n"),
            )
            .with(
                "clang",
                &["--version"],
                CommandOutput::ok("Ubuntu clang version 18.1.3\n"),
            )
            .with("llvm-config", &["--version"], CommandOutput::ok("18.1.3\n"))
            .with(
                "qemu-system-x86_64",
                &["--version"],
                CommandOutput::ok("QEMU emulator version 8.2.0\n"),
            )
            .with("make", &["--version"], CommandOutput::ok("GNU Make 4.3\n"))
    }

    fn linux_fs_with_kvm_rw() -> MockFs {
        MockFs::new()
            .with_file(
                OS_RELEASE_PATH,
                "PRETTY_NAME=\"Ubuntu 24.04.5 LTS\"\nNAME=\"Ubuntu\"\n",
            )
            .with_node(KVM_PATH, true, true, true)
    }

    #[test]
    fn healthy_host_all_ok_or_warn_only_on_non_linux() {
        let findings = run_all_checks(&healthy_runner(), &linux_fs_with_kvm_rw());
        assert!(findings
            .iter()
            .any(|f| f.id == "rustc" && f.severity == Severity::Ok));
        assert!(findings
            .iter()
            .any(|f| f.id == "cargo" && f.severity == Severity::Ok));
        assert!(findings
            .iter()
            .any(|f| f.id == "qemu" && f.severity == Severity::Ok));
        assert!(findings
            .iter()
            .any(|f| f.id == "kvm" && f.severity == Severity::Ok));
        assert!(findings
            .iter()
            .filter(|f| f.importance == Importance::Required)
            .all(|f| f.severity != Severity::Fail));
    }

    #[test]
    fn missing_rustc_is_required_fail() {
        let runner = MockRunner::new().with_default_not_found().with(
            "cargo",
            &["--version"],
            CommandOutput::ok("cargo 1.83.0\n"),
        );
        let findings = run_all_checks(&runner, &linux_fs_with_kvm_rw());
        let rustc = findings.iter().find(|f| f.id == "rustc").unwrap();
        assert_eq!(rustc.severity, Severity::Fail);
        assert_eq!(rustc.importance, Importance::Required);
    }

    #[test]
    fn missing_qemu_is_optional_warn_not_fail() {
        let runner = healthy_runner().with(
            "qemu-system-x86_64",
            &["--version"],
            CommandOutput::not_found("qemu-system-x86_64"),
        );
        // Also ensure qemu-img missing
        let findings = run_all_checks(&runner, &linux_fs_with_kvm_rw());
        let qemu = findings.iter().find(|f| f.id == "qemu").unwrap();
        assert_eq!(qemu.severity, Severity::Warn);
        assert_eq!(qemu.importance, Importance::Optional);
    }

    #[test]
    fn kvm_present_but_not_accessible_is_warn() {
        let fs = MockFs::new()
            .with_file(OS_RELEASE_PATH, "PRETTY_NAME=\"Ubuntu 24.04.5 LTS\"\n")
            .with_node(KVM_PATH, true, false, false);
        let findings = run_all_checks(&healthy_runner(), &fs);
        let kvm = findings.iter().find(|f| f.id == "kvm").unwrap();
        assert_eq!(kvm.severity, Severity::Warn);
        assert!(kvm.summary.contains("limited"));
    }

    #[test]
    fn unexpected_nonzero_exit_handled() {
        let runner = healthy_runner().with(
            "rustc",
            &["--version"],
            CommandOutput::failed(2, "confused rustc\n"),
        );
        let findings = run_all_checks(&runner, &linux_fs_with_kvm_rw());
        let rustc = findings.iter().find(|f| f.id == "rustc").unwrap();
        assert_eq!(rustc.severity, Severity::Fail);
        assert!(rustc.detail.as_ref().unwrap().contains("confused rustc"));
    }

    #[test]
    fn empty_success_is_warn() {
        let finding = classify_version_tool(
            "cargo",
            "Cargo",
            Importance::Required,
            "cargo",
            &CommandOutput::ok("\n\n"),
            "hint",
        );
        assert_eq!(finding.severity, Severity::Warn);
    }
}
