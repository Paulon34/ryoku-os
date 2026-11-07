//! First Boot Lab (Missions 005–006) — reference guest boot with serial capture.
//!
//! # Honesty contract
//!
//! - Matching Alpine serial markers means **reference Linux** console progress —
//!   **not** “Ryoku OS booted”.
//! - Without QEMU → SKIPPED; without the ISO file → NOT_RUN.
//! - QEMU process start ≠ Linux boot success.
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

    eprintln!(
        "first-boot iso_abs={} exists={}",
        iso_path.display(),
        iso_path.is_file()
    );

    if !iso_path.is_file() {
        results.push(missing_iso_result(lab_root, &iso_path));
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
    let markers = cfg.required_boot_markers();
    // PASS eligibility depends ONLY on the guest serial log — never stdout/stderr.
    // QEMU process streams are kept for diagnostics only (see detail / evidence).
    let missing = missing_markers(&serial_text, &markers);
    let serial_eligible = serial_markers_pass(&serial_text, &markers);

    if let Some(err) = &exec.spawn_error {
        results.push(
            CaseResult::new(
                "t2.reference_linux_boot",
                Outcome::Fail,
                "failed to spawn QEMU for reference boot",
            )
            .with_detail(err.clone()),
        );
        write_evidence(
            lab_root,
            &cfg,
            argv.accel_used.as_str(),
            &exec,
            &serial_text,
            &markers,
            &missing,
            "FAIL",
            "spawn_error",
        );
    } else if markers.is_empty() {
        results.push(CaseResult::new(
            "t2.reference_linux_boot",
            Outcome::Fail,
            "boot_sentinel / boot_markers missing from config — cannot verify boot",
        ));
        write_evidence(
            lab_root,
            &cfg,
            argv.accel_used.as_str(),
            &exec,
            &serial_text,
            &markers,
            &missing,
            "FAIL",
            "no_markers_configured",
        );
    } else if serial_eligible {
        results.push(
            CaseResult::new(
                "t2.reference_linux_boot",
                Outcome::Pass,
                format!(
                    "reference Linux *serial* matched markers {:?} (NOT Ryoku OS)",
                    markers
                ),
            )
            .with_detail(format!(
                "accel={} duration_ms={} timed_out={} exit={:?}\nserial_bytes={}\n\
                 pass_source=serial_log_only (stdout/stderr ignored for PASS)\n\
                 stdout_bytes={} stderr_bytes={}",
                argv.accel_used.as_str(),
                exec.duration_ms,
                exec.timed_out,
                exec.exit_code,
                serial_text.len(),
                exec.stdout.len(),
                exec.stderr.len()
            )),
        );
        write_evidence(
            lab_root,
            &cfg,
            argv.accel_used.as_str(),
            &exec,
            &serial_text,
            &markers,
            &missing,
            "PASS",
            "all_markers_matched_in_serial",
        );
    } else if exec.spawned() {
        results.push(
            CaseResult::new(
                "t2.reference_linux_boot",
                Outcome::Fail,
                format!(
                    "QEMU ran but serial markers missing before stop: {missing:?}"
                ),
            )
            .with_detail(format!(
                "accel={} duration_ms={} timed_out={} — refusing to claim boot without serial evidence\n\
                 pass_source=serial_log_only (stdout/stderr ignored for PASS)\n\
                 serial_tail={}\nstdout_tail={}\nstderr_tail={}",
                argv.accel_used.as_str(),
                exec.duration_ms,
                exec.timed_out,
                trim_tail(&serial_text, 500),
                trim_tail(&exec.stdout, 200),
                trim_tail(&exec.stderr, 200)
            )),
        );
        write_evidence(
            lab_root,
            &cfg,
            argv.accel_used.as_str(),
            &exec,
            &serial_text,
            &markers,
            &missing,
            "FAIL",
            if serial_text.is_empty() {
                "empty_serial"
            } else {
                "markers_incomplete_in_serial"
            },
        );
    } else {
        results.push(CaseResult::new(
            "t2.reference_linux_boot",
            Outcome::Fail,
            "unexpected exec state",
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
        Ok(cfg) if cfg.iso.is_some() && (!cfg.required_boot_markers().is_empty()) => {
            CaseResult::new(
                "t2.config",
                Outcome::Pass,
                format!(
                    "loaded `{}` with iso + markers {:?}",
                    cfg.name,
                    cfg.required_boot_markers()
                ),
            )
        }
        Ok(_) => CaseResult::new(
            "t2.config",
            Outcome::Fail,
            "config missing iso or boot markers",
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

/// Classify a missing ISO: plain NOT_RUN vs path-inconsistency FAIL (sidecar without ISO).
fn missing_iso_result(lab_root: &Path, iso_path: &Path) -> CaseResult {
    let name = iso_path
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("reference.iso");
    let run_dir = lab_root.join("run");
    let sha = run_dir.join(format!("{name}.sha256"));
    let asc = run_dir.join(format!("{name}.asc"));
    let sidecar_present = sha.is_file() || asc.is_file();

    if sidecar_present {
        CaseResult::new(
            "t2.reference_linux_boot",
            Outcome::Fail,
            format!(
                "path inconsistency: fetch sidecars present under {} but ISO missing at {}",
                run_dir.display(),
                iso_path.display()
            ),
        )
        .with_detail(format!(
            "lab_root_abs={}\niso_abs={}\nsha256_sidecar={}\nasc_sidecar={}\n\
             Refusing PASS/NOT_RUN ambiguity — ISO was fetched but harness cannot open it.",
            lab_root.display(),
            iso_path.display(),
            sha.is_file(),
            asc.is_file()
        ))
    } else {
        CaseResult::new(
            "t2.reference_linux_boot",
            Outcome::NotRun,
            format!("reference ISO not present at {}", iso_path.display()),
        )
        .with_detail(format!(
            "lab_root_abs={}\niso_abs={}\n\
             Fetch only after authorization: \
             RYOKU_FETCH_EXECUTE=1 tests/qemu/scripts/fetch-reference-image.sh \
             (default is dry-run). This is Alpine — not Ryoku OS.",
            lab_root.display(),
            iso_path.display()
        ))
    }
}

pub(crate) fn read_serial(cfg: &VmConfig) -> String {
    cfg.serial_log
        .as_ref()
        .and_then(|p| fs::read_to_string(p).ok())
        .unwrap_or_default()
}

pub(crate) fn trim_tail(s: &str, max: usize) -> String {
    let t = s.trim();
    if t.len() <= max {
        t.to_string()
    } else {
        format!("…{}", &t[t.len() - max..])
    }
}

pub(crate) fn run_boot_until_sentinel_or_timeout(
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
    let markers = cfg.required_boot_markers();
    let mut quit_sent = false;

    loop {
        // Check serial file for *all* required markers before requesting quit.
        if !markers.is_empty() {
            let serial = read_serial(cfg);
            if missing_markers(&serial, &markers).is_empty()
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

/// Return markers that are not present in `haystack`.
#[must_use]
pub fn missing_markers(haystack: &str, markers: &[String]) -> Vec<String> {
    markers
        .iter()
        .filter(|m| !haystack.contains(m.as_str()))
        .cloned()
        .collect()
}

/// True only when every required marker appears in the **guest serial log**.
///
/// Empty serial, empty marker list, or any missing marker → not eligible for PASS.
/// Callers must not concatenate QEMU stdout/stderr into `serial`.
#[must_use]
pub fn serial_markers_pass(serial: &str, markers: &[String]) -> bool {
    !markers.is_empty() && !serial.is_empty() && missing_markers(serial, markers).is_empty()
}

/// Evaluate PASS eligibility using **only** `serial`.
///
/// `stdout` / `stderr` are accepted so callers (and tests) can prove that markers
/// present solely in process streams cannot produce a PASS.
#[must_use]
pub fn reference_boot_pass_eligible(
    serial: &str,
    stdout: &str,
    stderr: &str,
    markers: &[String],
) -> bool {
    let _ = (stdout, stderr); // intentionally unused for PASS — diagnostics only
    serial_markers_pass(serial, markers)
}

#[allow(clippy::too_many_arguments)]
fn write_evidence(
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
    let path = dir.join("verified-boot-evidence.json");
    // Minimal JSON without a serde dependency (stdlib only).
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
         \"reference_not_ryoku\": true,\n\
         \"image\": \"alpine-virt-3.21.9\",\n\
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
    fn sentinel_helper() {
        assert!(serial_matches_sentinel("foo\nlogin:\n", "login:"));
        assert!(!serial_matches_sentinel("booting...", "login:"));
    }

    #[test]
    fn alpine_markers_require_all() {
        let markers = vec!["Alpine".to_string(), "login:".to_string()];
        assert!(missing_markers("Welcome to Alpine\n\nlogin:", &markers).is_empty());
        assert_eq!(
            missing_markers("login:", &markers),
            vec!["Alpine".to_string()]
        );
        assert_eq!(
            missing_markers("Alpine Linux", &markers),
            vec!["login:".to_string()]
        );
    }

    fn alpine_markers() -> Vec<String> {
        vec!["Alpine".to_string(), "login:".to_string()]
    }

    #[test]
    fn markers_only_in_stdout_not_pass() {
        let markers = alpine_markers();
        let stdout = "Welcome to Alpine\n\nlocalhost login:";
        assert!(
            !reference_boot_pass_eligible("", stdout, "", &markers),
            "stdout-only markers must not PASS"
        );
    }

    #[test]
    fn markers_only_in_stderr_not_pass() {
        let markers = alpine_markers();
        let stderr = "Alpine Linux\nlogin:";
        assert!(
            !reference_boot_pass_eligible("", "", stderr, &markers),
            "stderr-only markers must not PASS"
        );
    }

    #[test]
    fn markers_split_across_stdout_and_serial_not_pass() {
        let markers = alpine_markers();
        // "Alpine" only on stdout; "login:" only on serial — must not PASS.
        assert!(!reference_boot_pass_eligible(
            "localhost login:",
            "Welcome to Alpine",
            "",
            &markers
        ));
        // Reverse split.
        assert!(!reference_boot_pass_eligible(
            "Welcome to Alpine",
            "login:",
            "",
            &markers
        ));
    }

    #[test]
    fn all_markers_in_serial_eligible_for_pass() {
        let markers = alpine_markers();
        assert!(reference_boot_pass_eligible(
            "Welcome to Alpine Linux\n\nlocalhost login:",
            "qemu monitor noise Alpine login:", // decoy — must be ignored
            "stderr Alpine login:",
            &markers
        ));
        assert!(serial_markers_pass(
            "Welcome to Alpine Linux\n\nlocalhost login:",
            &markers
        ));
    }

    #[test]
    fn empty_serial_not_pass() {
        let markers = alpine_markers();
        assert!(!serial_markers_pass("", &markers));
        assert!(!reference_boot_pass_eligible(
            "",
            "Alpine\nlogin:",
            "Alpine\nlogin:",
            &markers
        ));
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
            .any(|r| r.id == "t2.reference_linux_boot" && r.outcome == Outcome::NotRun));
        assert!(results
            .iter()
            .any(|r| r.id == "t2.ryoku_os_boot" && r.outcome == Outcome::NotRun));
        assert!(results
            .iter()
            .any(|r| r.id == "t2.policy_reference_not_ryoku" && r.outcome == Outcome::Pass));
        assert!(!results.iter().any(|r| r.outcome == Outcome::Fail));
        assert!(!results
            .iter()
            .any(|r| r.id == "t2.reference_linux_boot" && r.outcome == Outcome::Pass));
    }

    #[test]
    fn does_not_claim_ryoku_on_alpine_sentinel() {
        // Even if serial matched Alpine login, ryoku case stays NOT_RUN by construction.
        assert_eq!(ryoku_not_claimed().outcome, Outcome::NotRun);
    }
}
