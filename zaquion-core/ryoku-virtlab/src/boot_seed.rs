//! Boot Seed / T3 (Mission 008) — first-party `ryoku-init` + lab kernel/initrd.
//!
//! # Honesty contract
//!
//! - Marker `RYOKU_BOOT_SEED_READY` on **guest serial** may PASS `t3.boot_seed`.
//! - That is **not** a finished Ryoku OS product boot.
//! - Without QEMU → SKIPPED; without kernel/initrd files → NOT_RUN.
//! - Mission 008 stops before authorized T3 guest execution; harness is ready.

use std::fs;
use std::path::Path;

use crate::argv::build_qemu_argv;
use crate::boot::{
    missing_markers, read_serial, run_boot_until_sentinel_or_timeout, serial_markers_pass,
    trim_tail,
};
use crate::config::VmConfig;
use crate::status::{CaseResult, Outcome};
use crate::tools::{detect_tools, ToolProbe};

const BOOT_SEED_CONFIG: &str = "configs/t3-boot-seed.rvl.conf";
const BOOT_SEED_MARKER: &str = "RYOKU_BOOT_SEED_READY";
const PID1_IDENTITY_MARKER: &str = "ryoku-init: pid=1";

/// Guest T3 QEMU spawn requires explicit authorization (`RYOKU_T3_EXECUTE=1`).
///
/// Mission 009: prevents accidental local/CI T3 even when kernel+initrd exist.
#[must_use]
pub fn t3_guest_execute_authorized() -> bool {
    std::env::var("RYOKU_T3_EXECUTE").ok().as_deref() == Some("1")
}

/// Run Boot Seed / T3 cases. Safe when QEMU or kernel/initrd are absent.
pub fn run_boot_seed<P: ToolProbe>(lab_root: &Path, probe: &P) -> Vec<CaseResult> {
    let tools = detect_tools(probe);
    let mut results = vec![
        case_policy_seed_not_product(),
        case_config_loads(lab_root),
        case_argv_kernel_initrd(lab_root, &tools),
        case_marker_constant(),
    ];

    if !tools.qemu_present() {
        results.push(
            CaseResult::new(
                "t3.qemu_required",
                Outcome::Skipped,
                "QEMU absent — boot-seed guest not started",
            )
            .with_detail(
                "Install qemu-system-x86_64 only with host authorization. \
                 Missing QEMU must not fail T0/T1/T2 or `cargo test`."
                    .to_string(),
            ),
        );
        results.push(CaseResult::new(
            "t3.boot_seed",
            Outcome::NotRun,
            "Boot seed guest not attempted (QEMU absent)",
        ));
        results.push(ryoku_product_not_claimed());
        return results;
    }

    let cfg_path = lab_root.join(BOOT_SEED_CONFIG);
    let cfg = match VmConfig::load_file(&cfg_path, lab_root) {
        Ok(cfg) => cfg,
        Err(err) => {
            results.push(CaseResult::new(
                "t3.boot_seed",
                Outcome::Fail,
                format!("cannot load boot-seed config: {err}"),
            ));
            results.push(ryoku_product_not_claimed());
            return results;
        }
    };

    let kernel = match &cfg.kernel {
        Some(p) => p.clone(),
        None => {
            results.push(CaseResult::new(
                "t3.boot_seed",
                Outcome::Fail,
                "boot-seed config has no kernel=",
            ));
            results.push(ryoku_product_not_claimed());
            return results;
        }
    };
    let initrd = match &cfg.initrd {
        Some(p) => p.clone(),
        None => {
            results.push(CaseResult::new(
                "t3.boot_seed",
                Outcome::Fail,
                "boot-seed config has no initrd=",
            ));
            results.push(ryoku_product_not_claimed());
            return results;
        }
    };

    eprintln!(
        "boot-seed kernel_abs={} exists={} initrd_abs={} exists={}",
        kernel.display(),
        kernel.is_file(),
        initrd.display(),
        initrd.is_file()
    );

    if !kernel.is_file() || !initrd.is_file() {
        results.push(missing_assets_result(lab_root, &kernel, &initrd));
        results.push(ryoku_product_not_claimed());
        return results;
    }

    if !t3_guest_execute_authorized() {
        results.push(
            CaseResult::new(
                "t3.boot_seed",
                Outcome::NotRun,
                "T3 guest spawn gated — set RYOKU_T3_EXECUTE=1 only under authorization",
            )
            .with_detail(
                "Mission 009 harness guard: kernel/initrd may exist, but QEMU guest boot \
                 is refused without RYOKU_T3_EXECUTE=1 (authorized boot-seed-t3 workflow). \
                 Accidental local `boot-seed` must not claim a real T3 run."
                    .to_string(),
            ),
        );
        results.push(ryoku_product_not_claimed());
        return results;
    }

    let accel = match tools.select_accel(cfg.accel) {
        Ok(a) => a,
        Err(err) => {
            results.push(
                CaseResult::new(
                    "t3.boot_seed",
                    Outcome::Skipped,
                    "acceleration prerequisites not met",
                )
                .with_detail(err),
            );
            results.push(ryoku_product_not_claimed());
            return results;
        }
    };

    let argv = match build_qemu_argv("qemu-system-x86_64", &cfg, accel) {
        Ok(a) => a,
        Err(err) => {
            results.push(CaseResult::new(
                "t3.boot_seed",
                Outcome::Fail,
                format!("argv build failed: {err}"),
            ));
            results.push(ryoku_product_not_claimed());
            return results;
        }
    };

    if let Some(serial) = &cfg.serial_log {
        if let Some(parent) = serial.parent() {
            let _ = fs::create_dir_all(parent);
        }
        let _ = fs::write(serial, "");
    }

    let exec = run_boot_until_sentinel_or_timeout(&argv, &cfg);
    let serial_text = read_serial(&cfg);
    let markers = cfg.required_boot_markers();
    let missing = missing_markers(&serial_text, &markers);
    let serial_eligible = serial_markers_pass(&serial_text, &markers);

    if let Some(err) = &exec.spawn_error {
        results.push(
            CaseResult::new(
                "t3.boot_seed",
                Outcome::Fail,
                "failed to spawn QEMU for boot seed",
            )
            .with_detail(err.clone()),
        );
        write_seed_evidence(
            lab_root,
            &cfg,
            &format!("{accel:?}"),
            &exec,
            &serial_text,
            &markers,
            &missing,
            "FAIL",
            "spawn_error",
        );
        results.push(ryoku_product_not_claimed());
        return results;
    }

    if serial_eligible {
        results.push(
            CaseResult::new(
                "t3.boot_seed",
                Outcome::Pass,
                "guest serial contains RYOKU_BOOT_SEED_READY (first-party init)",
            )
            .with_detail(format!("serial_tail=\n{}", trim_tail(&serial_text, 600))),
        );
        write_seed_evidence(
            lab_root,
            &cfg,
            &format!("{accel:?}"),
            &exec,
            &serial_text,
            &markers,
            &missing,
            "PASS",
            "all_markers_matched_in_serial",
        );
    } else {
        results.push(
            CaseResult::new(
                "t3.boot_seed",
                Outcome::Fail,
                format!("boot seed markers missing: {missing:?}"),
            )
            .with_detail(format!(
                "timed_out={} duration_ms={}\nserial_tail=\n{}",
                exec.timed_out,
                exec.duration_ms,
                trim_tail(&serial_text, 800)
            )),
        );
        write_seed_evidence(
            lab_root,
            &cfg,
            &format!("{accel:?}"),
            &exec,
            &serial_text,
            &markers,
            &missing,
            "FAIL",
            "markers_missing_in_serial",
        );
    }

    results.push(ryoku_product_not_claimed());
    results
}

fn case_policy_seed_not_product() -> CaseResult {
    CaseResult::new(
        "t3.policy_seed_not_product_boot",
        Outcome::Pass,
        "policy recorded: boot seed ≠ Ryoku OS product boot",
    )
    .with_detail(
        "See docs/testing/boot-seed.md and ADR-0002. Marker PASS only proves \
         first-party ryoku-init ran as guest PID 1 under a temporary lab kernel."
            .to_string(),
    )
}

fn case_config_loads(lab_root: &Path) -> CaseResult {
    let path = lab_root.join(BOOT_SEED_CONFIG);
    match VmConfig::load_file(&path, lab_root) {
        Ok(cfg)
            if cfg.kernel.is_some()
                && cfg.initrd.is_some()
                && cfg.append.is_some()
                && cfg
                    .required_boot_markers()
                    .iter()
                    .any(|m| m == PID1_IDENTITY_MARKER)
                && cfg
                    .required_boot_markers()
                    .iter()
                    .any(|m| m == BOOT_SEED_MARKER) =>
        {
            CaseResult::new(
                "t3.config",
                Outcome::Pass,
                format!(
                    "loaded `{}` with kernel+initrd+append + markers {:?}",
                    cfg.name,
                    cfg.required_boot_markers()
                ),
            )
        }
        Ok(_) => CaseResult::new(
            "t3.config",
            Outcome::Fail,
            "config missing kernel, initrd, append, or required pid=1 + READY markers",
        ),
        Err(err) => CaseResult::new("t3.config", Outcome::Fail, err.to_string()),
    }
}

fn case_argv_kernel_initrd(lab_root: &Path, tools: &crate::tools::ToolsReport) -> CaseResult {
    let path = lab_root.join(BOOT_SEED_CONFIG);
    let cfg = match VmConfig::load_file(&path, lab_root) {
        Ok(c) => c,
        Err(err) => {
            return CaseResult::new("t3.argv_tcg", Outcome::Fail, err.to_string());
        }
    };
    match build_qemu_argv("qemu-system-x86_64", &cfg, crate::tools::AccelChoice::Tcg) {
        Ok(argv) => {
            let line = argv.as_command_line_parts().join(" ");
            let ok = line.contains("-accel")
                && line.contains("tcg")
                && line.contains("-kernel")
                && line.contains("-initrd")
                && line.contains("-append")
                && line.contains("console=ttyS0")
                && !line.contains("/dev/sda")
                && !line.contains("media=cdrom");
            if ok {
                CaseResult::new(
                    "t3.argv_tcg",
                    Outcome::Pass,
                    format!(
                        "TCG kernel+initrd argv ok (kvm_usable={})",
                        tools.kvm_usable
                    ),
                )
                .with_detail(line)
            } else {
                CaseResult::new("t3.argv_tcg", Outcome::Fail, "argv missing expected flags")
                    .with_detail(line)
            }
        }
        Err(err) => CaseResult::new("t3.argv_tcg", Outcome::Fail, err),
    }
}

fn case_marker_constant() -> CaseResult {
    if BOOT_SEED_MARKER == "RYOKU_BOOT_SEED_READY" && PID1_IDENTITY_MARKER == "ryoku-init: pid=1" {
        CaseResult::new(
            "t3.marker_identity",
            Outcome::Pass,
            "serial markers require ryoku-init: pid=1 AND RYOKU_BOOT_SEED_READY",
        )
    } else {
        CaseResult::new("t3.marker_identity", Outcome::Fail, "marker constant drift")
    }
}

fn ryoku_product_not_claimed() -> CaseResult {
    CaseResult::new(
        "t3.ryoku_os_product_boot",
        Outcome::NotRun,
        "Ryoku OS product boot NOT claimed — boot seed is init prototype only",
    )
}

fn missing_assets_result(lab_root: &Path, kernel: &Path, initrd: &Path) -> CaseResult {
    CaseResult::new(
        "t3.boot_seed",
        Outcome::NotRun,
        format!(
            "boot-seed assets missing (kernel_exists={} initrd_exists={})",
            kernel.is_file(),
            initrd.is_file()
        ),
    )
    .with_detail(format!(
        "lab_root_abs={}\nkernel_abs={}\ninitrd_abs={}\n\
         Documented procedure: docs/testing/boot-seed.md\n\
         Pack initramfs (authorized): RYOKU_INITRAMFS_EXECUTE=1 \
         tests/qemu/scripts/build-boot-seed-initramfs.sh\n\
         Kernel: pin/extract per fixtures/boot-seed-kernel.manifest — \
         Mission 008 does not download kernels.\n\
         Real guest T3 requires separate authorization.",
        lab_root.display(),
        kernel.display(),
        initrd.display()
    ))
}

#[allow(clippy::too_many_arguments)]
fn write_seed_evidence(
    lab_root: &Path,
    cfg: &VmConfig,
    accel: &str,
    exec: &crate::exec::ExecResult,
    serial_text: &str,
    markers: &[String],
    missing: &[String],
    verdict: &str,
    reason: &str,
) {
    let dir = lab_root.join("results");
    let _ = fs::create_dir_all(&dir);
    let path = dir.join("boot-seed-evidence.json");
    let escaped_serial_tail = json_escape(&trim_tail(serial_text, 800));
    let markers_json = markers
        .iter()
        .map(|m| format!("\"{}\"", json_escape(m)))
        .collect::<Vec<_>>()
        .join(",");
    let missing_json = missing
        .iter()
        .map(|m| format!("\"{}\"", json_escape(m)))
        .collect::<Vec<_>>()
        .join(",");
    let body = format!(
        "{{\n\
         \"verdict\": \"{verdict}\",\n\
         \"reason\": \"{reason}\",\n\
         \"seed_not_product_boot\": true,\n\
         \"marker\": \"{BOOT_SEED_MARKER}\",\n\
         \"vm\": {{\n\
         \"name\": \"{}\",\n\
         \"memory_mb\": {},\n\
         \"cpus\": {},\n\
         \"timeout_secs\": {},\n\
         \"accel\": \"{accel}\",\n\
         \"network\": \"none\"\n\
         }},\n\
         \"duration_ms\": {},\n\
         \"timed_out\": {},\n\
         \"exit_code\": {},\n\
         \"markers_required\": [{markers_json}],\n\
         \"markers_missing\": [{missing_json}],\n\
         \"serial_bytes\": {},\n\
         \"serial_tail\": \"{escaped_serial_tail}\"\n\
         }}\n",
        cfg.name,
        cfg.memory_mb,
        cfg.cpus,
        cfg.timeout_secs,
        exec.duration_ms,
        exec.timed_out,
        exec.exit_code
            .map(|c| c.to_string())
            .unwrap_or_else(|| "null".to_string()),
        serial_text.len(),
    );
    let _ = fs::write(path, body);
}

fn json_escape(s: &str) -> String {
    s.replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
        .replace('\t', "\\t")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tools::ToolProbe;
    use std::path::{Path, PathBuf};

    struct NoQemu;
    impl ToolProbe for NoQemu {
        fn version_line(&self, _: &str, _: &[&str]) -> Option<String> {
            None
        }
        fn path_exists(&self, _: &Path) -> bool {
            false
        }
        fn path_readable(&self, _: &Path) -> bool {
            false
        }
        fn path_writable(&self, _: &Path) -> bool {
            false
        }
    }

    #[test]
    fn boot_seed_skips_without_qemu() {
        let lab = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../tests/qemu");
        let results = run_boot_seed(&lab, &NoQemu);
        assert!(results
            .iter()
            .any(|r| r.id == "t3.qemu_required" && r.outcome == Outcome::Skipped));
        assert!(results
            .iter()
            .any(|r| r.id == "t3.boot_seed" && r.outcome == Outcome::NotRun));
        assert!(results
            .iter()
            .any(|r| r.id == "t3.ryoku_os_product_boot" && r.outcome == Outcome::NotRun));
        assert!(results
            .iter()
            .any(|r| r.id == "t3.policy_seed_not_product_boot" && r.outcome == Outcome::Pass));
        assert!(results
            .iter()
            .any(|r| r.id == "t3.config" && r.outcome == Outcome::Pass));
        assert!(!results.iter().any(|r| r.outcome == Outcome::Fail));
        assert!(!results
            .iter()
            .any(|r| r.id == "t3.boot_seed" && r.outcome == Outcome::Pass));
    }

    fn required_markers() -> Vec<String> {
        vec![
            PID1_IDENTITY_MARKER.to_string(),
            BOOT_SEED_MARKER.to_string(),
        ]
    }

    #[test]
    fn serial_marker_must_come_from_guest_text() {
        let markers = required_markers();
        assert!(!serial_markers_pass("", &markers));
        assert!(!serial_markers_pass("QEMU emulator version", &markers));
        // READY alone is insufficient.
        assert!(!serial_markers_pass("RYOKU_BOOT_SEED_READY\n", &markers));
        // pid=1 alone is insufficient.
        assert!(!serial_markers_pass("ryoku-init: pid=1\n", &markers));
        // Non-PID1 identity must not PASS even with READY decoy.
        assert!(!serial_markers_pass(
            "ryoku-init: pid=42 seed=mission-008\nRYOKU_BOOT_SEED_READY\n",
            &markers
        ));
        assert!(serial_markers_pass(
            "ryoku-init: pid=1 seed=mission-008\nRYOKU_BOOT_SEED_READY\n",
            &markers
        ));
    }

    #[test]
    fn qemu_process_streams_cannot_fake_serial_pass() {
        let markers = required_markers();
        let stdout = format!("{PID1_IDENTITY_MARKER}\n{BOOT_SEED_MARKER}\n");
        let stderr = stdout.clone();
        assert!(
            !crate::boot::reference_boot_pass_eligible("", &stdout, &stderr, &markers),
            "markers only in QEMU stdout/stderr must not PASS t3.boot_seed"
        );
        assert!(crate::boot::reference_boot_pass_eligible(
            &format!("{PID1_IDENTITY_MARKER} seed=mission-008\n{BOOT_SEED_MARKER}\n"),
            &stdout,
            &stderr,
            &markers
        ));
    }

    #[test]
    fn product_boot_stays_not_run() {
        assert_eq!(ryoku_product_not_claimed().outcome, Outcome::NotRun);
    }

    #[test]
    fn t3_execute_gate_defaults_closed() {
        // Ensure the helper is false unless the env var is explicitly "1".
        // (Test process must not inherit RYOKU_T3_EXECUTE=1 from a parent.)
        let prev = std::env::var_os("RYOKU_T3_EXECUTE");
        std::env::remove_var("RYOKU_T3_EXECUTE");
        assert!(!t3_guest_execute_authorized());
        std::env::set_var("RYOKU_T3_EXECUTE", "0");
        assert!(!t3_guest_execute_authorized());
        std::env::set_var("RYOKU_T3_EXECUTE", "1");
        assert!(t3_guest_execute_authorized());
        match prev {
            Some(v) => std::env::set_var("RYOKU_T3_EXECUTE", v),
            None => std::env::remove_var("RYOKU_T3_EXECUTE"),
        }
    }
}
