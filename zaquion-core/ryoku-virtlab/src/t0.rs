//! Harness T0 — validation that always runs (no QEMU required).

use std::path::Path;

use crate::argv::build_qemu_argv;
use crate::config::{AccelMode, VmConfig};
use crate::security::{is_blocked_physical_device, validate_optional_path, PathRole};
use crate::status::{CaseResult, Outcome};
use crate::tools::{detect_tools, AccelChoice, ToolProbe};

/// Run the T0 suite against fixtures under `lab_root` (typically `tests/qemu`).
pub fn run_t0<P: ToolProbe>(lab_root: &Path, probe: &P) -> Vec<CaseResult> {
    vec![
        case_lab_layout(lab_root),
        case_valid_config(lab_root),
        case_block_physical_device_literal(),
        case_block_physical_in_config(lab_root),
        case_invalid_path_escape(lab_root),
        case_absolute_path_rejected(lab_root),
        case_safe_argv(lab_root),
        case_tool_detection(probe),
        case_timeout_limit_enforced(lab_root),
        case_mocked_accel_selection(probe),
    ]
}

fn case_lab_layout(lab_root: &Path) -> CaseResult {
    let needed = ["fixtures", "configs", "expectations", "run", "results"];
    let mut missing = Vec::new();
    for name in needed {
        if !lab_root.join(name).exists() {
            missing.push(name);
        }
    }
    if missing.is_empty() {
        CaseResult::new(
            "t0.lab_layout",
            Outcome::Pass,
            "Virtual Lab directories present under tests/qemu",
        )
    } else {
        CaseResult::new(
            "t0.lab_layout",
            Outcome::Fail,
            format!("missing directories: {}", missing.join(", ")),
        )
    }
}

fn case_valid_config(lab_root: &Path) -> CaseResult {
    let path = lab_root.join("configs/t1-emulator-smoke.rvl.conf");
    match VmConfig::load_file(&path, lab_root) {
        Ok(cfg) if cfg.is_emulator_only() => CaseResult::new(
            "t0.valid_config",
            Outcome::Pass,
            format!("loaded `{}` (emulator-only)", cfg.name),
        ),
        Ok(cfg) => CaseResult::new(
            "t0.valid_config",
            Outcome::Fail,
            format!(
                "expected emulator-only fixture, got disk/kernel for {}",
                cfg.name
            ),
        ),
        Err(err) => CaseResult::new(
            "t0.valid_config",
            Outcome::Fail,
            format!("failed to load valid fixture: {err}"),
        ),
    }
}

fn case_block_physical_device_literal() -> CaseResult {
    let samples = [
        "/dev/sda",
        "/dev/sda1",
        "/dev/nvme0n1",
        "/dev/nvme0n1p1",
        "/dev/disk/by-uuid/abc",
    ];
    let all_blocked = samples.iter().all(|s| is_blocked_physical_device(s));
    if all_blocked {
        CaseResult::new(
            "t0.block_physical_literal",
            Outcome::Pass,
            "physical device path detector blocks sd/nvme/disk samples",
        )
    } else {
        CaseResult::new(
            "t0.block_physical_literal",
            Outcome::Fail,
            "detector failed to block one or more physical device samples",
        )
    }
}

fn case_block_physical_in_config(lab_root: &Path) -> CaseResult {
    let path = lab_root.join("configs/invalid-physical-disk.rvl.conf");
    match VmConfig::load_file(&path, lab_root) {
        Err(err) => {
            let msg = err.to_string();
            if msg.contains("physical") || msg.contains("/dev/sda") || msg.contains("security") {
                CaseResult::new(
                    "t0.block_physical_config",
                    Outcome::Pass,
                    "config with disk=/dev/sda rejected",
                )
                .with_detail(msg)
            } else {
                CaseResult::new(
                    "t0.block_physical_config",
                    Outcome::Fail,
                    format!("rejected for unexpected reason: {msg}"),
                )
            }
        }
        Ok(_) => CaseResult::new(
            "t0.block_physical_config",
            Outcome::Fail,
            "config with physical disk was accepted (security failure)",
        ),
    }
}

fn case_invalid_path_escape(lab_root: &Path) -> CaseResult {
    match validate_optional_path("../kernel/vmlinuz", PathRole::Kernel, lab_root) {
        Err(_) => CaseResult::new(
            "t0.invalid_path_escape",
            Outcome::Pass,
            "parent-dir escape rejected",
        ),
        Ok(p) => CaseResult::new(
            "t0.invalid_path_escape",
            Outcome::Fail,
            format!("escape incorrectly allowed: {}", p.display()),
        ),
    }
}

fn case_absolute_path_rejected(lab_root: &Path) -> CaseResult {
    match validate_optional_path("/tmp/evil.qcow2", PathRole::Disk, lab_root) {
        Err(_) => CaseResult::new(
            "t0.absolute_path_rejected",
            Outcome::Pass,
            "absolute host path rejected",
        ),
        Ok(_) => CaseResult::new(
            "t0.absolute_path_rejected",
            Outcome::Fail,
            "absolute path was accepted",
        ),
    }
}

fn case_safe_argv(lab_root: &Path) -> CaseResult {
    let path = lab_root.join("configs/t1-emulator-smoke.rvl.conf");
    let cfg = match VmConfig::load_file(&path, lab_root) {
        Ok(cfg) => cfg,
        Err(err) => {
            return CaseResult::new(
                "t0.safe_argv",
                Outcome::Fail,
                format!("cannot load config for argv test: {err}"),
            );
        }
    };
    match build_qemu_argv("qemu-system-x86_64", &cfg, AccelChoice::Tcg) {
        Ok(argv) => {
            let joined = argv.as_command_line_parts().join(" ");
            let ok = argv
                .args
                .windows(2)
                .any(|w| w[0] == "-accel" && w[1] == "tcg")
                && argv
                    .args
                    .windows(2)
                    .any(|w| w[0] == "-nic" && w[1] == "none")
                && !joined.contains("/dev/sda")
                && !argv.args.iter().any(|a| a.contains('`') || a.contains('$'));
            if ok {
                CaseResult::new(
                    "t0.safe_argv",
                    Outcome::Pass,
                    "argv uses discrete flags, TCG, nic=none, no physical disks",
                )
                .with_detail(joined)
            } else {
                CaseResult::new(
                    "t0.safe_argv",
                    Outcome::Fail,
                    "argv failed safety assertions",
                )
                .with_detail(joined)
            }
        }
        Err(err) => CaseResult::new("t0.safe_argv", Outcome::Fail, err),
    }
}

fn case_tool_detection<P: ToolProbe>(probe: &P) -> CaseResult {
    let report = detect_tools(probe);
    let summary = format!(
        "qemu={} kvm_usable={} tcg_possible={} qemu-img={}",
        report.qemu_present(),
        report.kvm_usable,
        report.tcg_possible,
        report.qemu_img.is_some()
    );
    // Detection itself always "passes" as a T0 capability; absence is data, not failure.
    CaseResult::new(
        "t0.tool_detection",
        Outcome::Pass,
        "tool probe completed (absence is reported, not a T0 fail)",
    )
    .with_detail(summary)
}

fn case_timeout_limit_enforced(lab_root: &Path) -> CaseResult {
    let text = "\
name = too-long
memory_mb = 256
cpus = 1
timeout_secs = 99999
";
    match VmConfig::parse(text, lab_root) {
        Err(err) if err.to_string().contains("timeout") => CaseResult::new(
            "t0.timeout_limit",
            Outcome::Pass,
            "oversized timeout_secs rejected",
        ),
        Err(err) => CaseResult::new(
            "t0.timeout_limit",
            Outcome::Fail,
            format!("unexpected error: {err}"),
        ),
        Ok(_) => CaseResult::new(
            "t0.timeout_limit",
            Outcome::Fail,
            "oversized timeout was accepted",
        ),
    }
}

fn case_mocked_accel_selection<P: ToolProbe>(probe: &P) -> CaseResult {
    let report = detect_tools(probe);
    // Validate logic paths exist: Auto must succeed only if qemu present.
    if report.qemu_present() {
        match report.select_accel(AccelMode::Auto) {
            Ok(choice) => CaseResult::new(
                "t0.accel_selection",
                Outcome::Pass,
                format!("auto selected {}", choice.as_str()),
            ),
            Err(err) => CaseResult::new("t0.accel_selection", Outcome::Fail, err),
        }
    } else {
        match report.select_accel(AccelMode::Auto) {
            Err(_) => CaseResult::new(
                "t0.accel_selection",
                Outcome::Pass,
                "auto correctly errors when QEMU absent (T1 will SKIP)",
            ),
            Ok(_) => CaseResult::new(
                "t0.accel_selection",
                Outcome::Fail,
                "auto selected accel without QEMU",
            ),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tools::HostToolProbe;
    use std::path::PathBuf;

    fn repo_lab_root() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../tests/qemu")
    }

    #[test]
    fn t0_physical_literal_passes() {
        let r = case_block_physical_device_literal();
        assert_eq!(r.outcome, Outcome::Pass);
    }

    #[test]
    fn t0_tool_detection_with_host_probe() {
        let r = case_tool_detection(&HostToolProbe);
        assert_eq!(r.outcome, Outcome::Pass);
    }

    #[test]
    fn t0_escape_against_tmp_lab() {
        let lab = PathBuf::from("/tmp/ryoku-lab-does-not-need-to-exist");
        let r = case_invalid_path_escape(&lab);
        assert_eq!(r.outcome, Outcome::Pass);
    }

    #[test]
    fn t0_full_suite_no_fail_on_repo_fixtures() {
        let lab = repo_lab_root();
        assert!(
            lab.join("configs/t1-emulator-smoke.rvl.conf").is_file(),
            "missing lab fixtures at {}",
            lab.display()
        );
        let results = run_t0(&lab, &HostToolProbe);
        let fails: Vec<_> = results
            .iter()
            .filter(|r| r.outcome == Outcome::Fail)
            .map(|r| r.id.as_str())
            .collect();
        assert!(
            fails.is_empty(),
            "T0 FAIL cases: {fails:?} — full results: {results:?}"
        );
    }
}
