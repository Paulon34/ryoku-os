//! First Boot Lab (Mission 005) — reference guest boot with serial capture.
//!
//! # Honesty contract
//!
//! - Matching a serial sentinel on **Alpine** (or any third-party image) means
//!   **reference Linux** console progress — **not** “Ryoku OS booted”.
//! - Without QEMU → SKIPPED; without the ISO file → NOT_RUN.
//! - Never claim PASS without inspecting captured serial text / logs.

use std::fs;
use std::path::Path;
use std::time::Duration;

use crate::argv::build_qemu_argv;
use crate::config::{ShutdownMode, VmConfig};
use crate::status::{CaseResult, Outcome};
use crate::tools::{detect_tools, ToolProbe};

const FIRST_BOOT_CONFIG: &str = "configs/t2-reference-alpine.rvl.conf";

/// Run first-boot cases (T2). Safe when QEMU/ISO absent.
pub fn run_first_boot<P: ToolProbe>(lab_root: &Path, probe: &P) -> Vec<CaseResult> {
    let tools = detect_tools(probe);
    let mut results = Vec::new();

    results.push(case_reference_not_ryoku());
    results.push(case_config_loads(lab_root));
    results.push(case_argv_tcg_fallback(lab_root, &tools));

    if !tools.qemu_present() {
        results.push(
            CaseResult::new(
                "t2.qemu_required",
                Outcome::Skipped,
                "QEMU absent — first-boot guest not started",
            )
            .with_detail(
                "Install qemu-system-x86_64 only with host authorization. \
                 Missing QEMU must not fail T0 or `cargo test`."
                    .to_string(),
            ),
        );
        results.push(CaseResult::new(
            "t2.reference_linux_boot",
            Outcome::NotRun,
            "Reference Linux boot not attempted (QEMU absent)",
        ));
        results.push(CaseResult::new(
            "t2.ryoku_os_boot",
            Outcome::NotRun,
            "Ryoku OS boot NOT claimed — no Ryoku ISO exists",
        ));
        return results;
    }

    let cfg_path = lab_root.join(FIRST_BOOT_CONFIG);
    let cfg = match VmConfig::load_file(&cfg_path, lab_root) {
        Ok(cfg) => cfg,
        Err(err) => {
            results.push(CaseResult::new(
                "t2.reference_linux_boot",
                Outcome::Fail,
                format!("cannot load first-boot config: {err}"),
            ));
            results.push(ryoku_not_claimed());
            return results;
        }
    };

    let iso_path = match &cfg.iso {
        Some(p) => p.clone(),
        None => {
            results.push(CaseResult::new(
                "t2.reference_linux_boot",
                Outcome::Fail,
                "first-boot config has no iso= medium",
            ));
            results.push(ryoku_not_claimed());
            return results;
        }
    };

    if !iso_path.is_file() {
        results.push(
            CaseResult::new(
                "t2.reference_linux_boot",
                Outcome::NotRun,
                format!("reference ISO not present at {}", iso_path.display()),
            )
            .with_detail(
                "Fetch only after authorization: \
                 RYOKU_FETCH_EXECUTE=1 tests/qemu/scripts/fetch-reference-image.sh \
                 (default is dry-run). This is Alpine — not Ryoku OS."
                    .to_string(),
            ),
        );
        results.push(ryoku_not_claimed());
        return results;
    }

    let accel = match tools.select_accel(cfg.accel) {
        Ok(a) => a,
        Err(err) => {
            results.push(
                CaseResult::new(
                    "t2.reference_linux_boot",
                    Outcome::Skipped,
                    "acceleration prerequisites not met",
                )
                .with_detail(err),
            );
            results.push(ryoku_not_claimed());
            return results;
        }
    };

    let argv = match build_qemu_argv("qemu-system-x86_64", &cfg, accel) {
        Ok(a) => a,
        Err(err) => {
            results.push(CaseResult::new(
                "t2.reference_linux_boot",
                Outcome::Fail,
                format!("argv build failed: {err}"),
            ));
            results.push(ryoku_not_claimed());
            return results;
        }
    };

    if let Some(serial) = &cfg.serial_log {
        if let Some(parent) = serial.parent() {
            let _ = fs::create_dir_all(parent);
        }
        let _ = fs::write(serial, "");
    }

    // First-boot waits for sentinel OR timeout, then sends monitor `quit` (if configured).
    let exec = run_boot_until_sentinel_or_timeout(&argv, &cfg);

    let serial_text = read_serial(&cfg);
    let combined = format!("{}\n{}\n{}", exec.stdout, exec.stderr, serial_text);

    if let Some(err) = &exec.spawn_error {
        results.push(
            CaseResult::new(
                "t2.reference_linux_boot",
                Outcome::Fail,
                "failed to spawn QEMU for reference boot",
            )
            .with_detail(err.clone()),
        );
    } else if let Some(sentinel) = &cfg.boot_sentinel {
        if combined.contains(sentinel.as_str()) {
            results.push(
                CaseResult::new(
                    "t2.reference_linux_boot",
                    Outcome::Pass,
                    format!("reference Linux serial matched sentinel `{sentinel}` (NOT Ryoku OS)"),
                )
                .with_detail(format!(
                    "accel={} duration_ms={} timed_out={} exit={:?}\nserial_bytes={}",
                    argv.accel_used.as_str(),
                    exec.duration_ms,
                    exec.timed_out,
                    exec.exit_code,
                    serial_text.len()
                )),
            );
        } else if exec.spawned() {
            results.push(
                CaseResult::new(
                    "t2.reference_linux_boot",
                    Outcome::Fail,
                    format!(
                        "QEMU ran but serial sentinel `{sentinel}` not observed before stop"
                    ),
                )
                .with_detail(format!(
                    "accel={} duration_ms={} timed_out={} — refusing to claim boot without evidence\nserial_tail={}",
                    argv.accel_used.as_str(),
                    exec.duration_ms,
                    exec.timed_out,
                    trim_tail(&serial_text, 500)
                )),
            );
        } else {
            results.push(CaseResult::new(
                "t2.reference_linux_boot",
                Outcome::Fail,
                "unexpected exec state",
            ));
        }
    } else {
        results.push(CaseResult::new(
            "t2.reference_linux_boot",
            Outcome::Fail,
            "boot_sentinel missing from config — cannot verify boot",
        ));
    }

    results.push(ryoku_not_claimed());
    results
}

fn case_reference_not_ryoku() -> CaseResult {
    CaseResult::new(
        "t2.policy_reference_not_ryoku",
        Outcome::Pass,
        "policy recorded: reference Linux boot ≠ Ryoku OS boot",
    )
    .with_detail(
        "See docs/testing/reference-linux.md. Alpine (or any third-party guest) never \
         counts as a Ryoku product boot."
            .to_string(),
    )
}

fn case_config_loads(lab_root: &Path) -> CaseResult {
    let path = lab_root.join(FIRST_BOOT_CONFIG);
    match VmConfig::load_file(&path, lab_root) {
        Ok(cfg) if cfg.iso.is_some() && cfg.boot_sentinel.is_some() => CaseResult::new(
            "t2.config",
            Outcome::Pass,
            format!("loaded `{}` with iso + boot_sentinel", cfg.name),
        ),
        Ok(_) => CaseResult::new(
            "t2.config",
            Outcome::Fail,
            "config missing iso or boot_sentinel",
        ),
        Err(err) => CaseResult::new("t2.config", Outcome::Fail, err.to_string()),
    }
}

fn case_argv_tcg_fallback(lab_root: &Path, tools: &crate::tools::ToolsReport) -> CaseResult {
    let path = lab_root.join(FIRST_BOOT_CONFIG);
    let cfg = match VmConfig::load_file(&path, lab_root) {
        Ok(c) => c,
        Err(err) => {
            return CaseResult::new("t2.argv_tcg", Outcome::Fail, err.to_string());
        }
    };
    // Always validate TCG argv build (KVM may be unavailable).
    match build_qemu_argv("qemu-system-x86_64", &cfg, crate::tools::AccelChoice::Tcg) {
        Ok(argv) => {
            let line = argv.as_command_line_parts().join(" ");
            let ok = line.contains("-accel")
                && line.contains("tcg")
                && line.contains("media=cdrom")
                && !line.contains("/dev/sda");
            if ok {
                CaseResult::new(
                    "t2.argv_tcg",
                    Outcome::Pass,
                    format!("TCG argv ok (kvm_usable={})", tools.kvm_usable),
                )
                .with_detail(line)
            } else {
                CaseResult::new("t2.argv_tcg", Outcome::Fail, "argv missing expected flags")
                    .with_detail(line)
            }
        }
        Err(err) => CaseResult::new("t2.argv_tcg", Outcome::Fail, err),
    }
}

fn ryoku_not_claimed() -> CaseResult {
    CaseResult::new(
        "t2.ryoku_os_boot",
        Outcome::NotRun,
        "Ryoku OS boot NOT claimed — no Ryoku ISO / kernel under test",
    )
}

fn read_serial(cfg: &VmConfig) -> String {
    cfg.serial_log
        .as_ref()
        .and_then(|p| fs::read_to_string(p).ok())
        .unwrap_or_default()
}

fn trim_tail(s: &str, max: usize) -> String {
    let t = s.trim();
    if t.len() <= max {
        t.to_string()
    } else {
        format!("…{}", &t[t.len() - max..])
    }
}

fn run_boot_until_sentinel_or_timeout(
    argv: &crate::argv::QemuArgv,
    cfg: &VmConfig,
) -> crate::exec::ExecResult {
    use std::io::Write;
    use std::process::{Command, Stdio};
    use std::thread;
    use std::time::Instant;

    let timeout = Duration::from_secs(cfg.timeout_secs);
    let started = Instant::now();
    let mut cmd = Command::new(&argv.program);
    cmd.args(&argv.args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(err) => {
            return crate::exec::ExecResult {
                timed_out: false,
                exit_code: None,
                stdout: String::new(),
                stderr: String::new(),
                spawn_error: Some(format!("{}: {err}", argv.program)),
                duration_ms: started.elapsed().as_millis(),
            };
        }
    };

    let mut stdin = child.stdin.take();
    let mut stdout_pipe = child.stdout.take();
    let mut stderr_pipe = child.stderr.take();
    let sentinel = cfg.boot_sentinel.clone().unwrap_or_default();
    let mut quit_sent = false;

    loop {
        // Check serial file for sentinel early.
        if !sentinel.is_empty() {
            let serial = read_serial(cfg);
            if serial.contains(sentinel.as_str())
                && !quit_sent
                && matches!(cfg.shutdown, ShutdownMode::MonitorQuit)
            {
                if let Some(ref mut sin) = stdin {
                    let _ = sin.write_all(b"quit\n");
                    let _ = sin.flush();
                }
                quit_sent = true;
            }
        }

        match child.try_wait() {
            Ok(Some(status)) => {
                let mut stdout_buf = Vec::new();
                let mut stderr_buf = Vec::new();
                if let Some(ref mut out) = stdout_pipe {
                    let _ = std::io::Read::read_to_end(out, &mut stdout_buf);
                }
                if let Some(ref mut err) = stderr_pipe {
                    let _ = std::io::Read::read_to_end(err, &mut stderr_buf);
                }
                return crate::exec::ExecResult {
                    timed_out: false,
                    exit_code: status.code(),
                    stdout: String::from_utf8_lossy(&stdout_buf).into_owned(),
                    stderr: String::from_utf8_lossy(&stderr_buf).into_owned(),
                    spawn_error: None,
                    duration_ms: started.elapsed().as_millis(),
                };
            }
            Ok(None) => {
                if started.elapsed() >= timeout {
                    if !quit_sent && matches!(cfg.shutdown, ShutdownMode::MonitorQuit) {
                        if let Some(ref mut sin) = stdin {
                            let _ = sin.write_all(b"quit\n");
                            let _ = sin.flush();
                        }
                        // Brief grace for monitor quit before kill.
                        thread::sleep(Duration::from_millis(500));
                    }
                    let _ = child.kill();
                    let _ = child.wait();
                    let mut stdout_buf = Vec::new();
                    let mut stderr_buf = Vec::new();
                    if let Some(ref mut out) = stdout_pipe {
                        let _ = std::io::Read::read_to_end(out, &mut stdout_buf);
                    }
                    if let Some(ref mut err) = stderr_pipe {
                        let _ = std::io::Read::read_to_end(err, &mut stderr_buf);
                    }
                    return crate::exec::ExecResult {
                        timed_out: true,
                        exit_code: None,
                        stdout: String::from_utf8_lossy(&stdout_buf).into_owned(),
                        stderr: String::from_utf8_lossy(&stderr_buf).into_owned(),
                        spawn_error: None,
                        duration_ms: started.elapsed().as_millis(),
                    };
                }
                thread::sleep(Duration::from_millis(100));
            }
            Err(err) => {
                return crate::exec::ExecResult {
                    timed_out: false,
                    exit_code: None,
                    stdout: String::new(),
                    stderr: String::new(),
                    spawn_error: Some(format!("wait error: {err}")),
                    duration_ms: started.elapsed().as_millis(),
                };
            }
        }
    }
}

/// Pure helper for tests: does serial text contain the configured sentinel?
#[must_use]
pub fn serial_matches_sentinel(serial: &str, sentinel: &str) -> bool {
    !sentinel.is_empty() && serial.contains(sentinel)
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
    fn sentinel_helper() {
        assert!(serial_matches_sentinel("foo\nlogin:\n", "login:"));
        assert!(!serial_matches_sentinel("booting...", "login:"));
    }

    #[test]
    fn first_boot_skips_without_qemu() {
        let lab = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../tests/qemu");
        let results = run_first_boot(&lab, &NoQemu);
        assert!(results
            .iter()
            .any(|r| r.id == "t2.qemu_required" && r.outcome == Outcome::Skipped));
        assert!(results
            .iter()
            .any(|r| r.id == "t2.ryoku_os_boot" && r.outcome == Outcome::NotRun));
        assert!(results
            .iter()
            .any(|r| r.id == "t2.policy_reference_not_ryoku" && r.outcome == Outcome::Pass));
        assert!(!results.iter().any(|r| r.outcome == Outcome::Fail));
    }

    #[test]
    fn does_not_claim_ryoku_on_alpine_sentinel() {
        // Even if serial matched Alpine login, ryoku case stays NOT_RUN by construction.
        assert_eq!(ryoku_not_claimed().outcome, Outcome::NotRun);
    }
}
