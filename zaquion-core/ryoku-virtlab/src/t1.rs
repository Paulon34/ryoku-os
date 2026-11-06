//! Harness T1 — optional QEMU emulator smoke (never claims Ryoku OS boot without a guest).

use std::path::Path;
use std::time::Duration;

use crate::argv::build_qemu_argv;
use crate::config::VmConfig;
use crate::exec::run_argv_with_timeout;
use crate::status::{CaseResult, Outcome};
use crate::tools::{detect_tools, ToolProbe};

/// Run T1 cases. When QEMU is absent → SKIPPED with reason.
/// When QEMU is present but config is emulator-only → may PASS emulator_start,
/// while OS boot remains NOT_RUN (no bootable Ryoku/system image authorized).
pub fn run_t1<P: ToolProbe>(lab_root: &Path, probe: &P) -> Vec<CaseResult> {
    let tools = detect_tools(probe);
    let mut results = Vec::new();

    if !tools.qemu_present() {
        results.push(
            CaseResult::new(
                "t1.emulator_start",
                Outcome::Skipped,
                "QEMU absent — emulator start not attempted",
            )
            .with_detail(
                "qemu-system-x86_64 not found on PATH. No packages were installed. \
                 Install QEMU on the host outside this mission if T1 execution is required."
                    .to_string(),
            ),
        );
        results.push(
            CaseResult::new(
                "t1.os_boot",
                Outcome::NotRun,
                "OS boot not attempted (QEMU absent; no guest image authorized)",
            )
            .with_detail(
                "Mission 003 does not download third-party ISOs and has no Ryoku ISO. \
                 Distinguishing emulator start vs OS boot requires a bootable kernel/system \
                 under test in a later mission."
                    .to_string(),
            ),
        );
        return results;
    }

    let cfg_path = lab_root.join("configs/t1-emulator-smoke.rvl.conf");
    let cfg = match VmConfig::load_file(&cfg_path, lab_root) {
        Ok(cfg) => cfg,
        Err(err) => {
            results.push(CaseResult::new(
                "t1.emulator_start",
                Outcome::Fail,
                format!("cannot load T1 config: {err}"),
            ));
            results.push(CaseResult::new(
                "t1.os_boot",
                Outcome::NotRun,
                "OS boot not attempted (config load failed)",
            ));
            return results;
        }
    };

    let accel = match tools.select_accel(cfg.accel) {
        Ok(accel) => accel,
        Err(err) => {
            results.push(
                CaseResult::new(
                    "t1.emulator_start",
                    Outcome::Skipped,
                    "acceleration prerequisites not met",
                )
                .with_detail(err),
            );
            results.push(CaseResult::new(
                "t1.os_boot",
                Outcome::NotRun,
                "OS boot not attempted (accel unavailable)",
            ));
            return results;
        }
    };

    let qemu_bin = "qemu-system-x86_64";
    let argv = match build_qemu_argv(qemu_bin, &cfg, accel) {
        Ok(argv) => argv,
        Err(err) => {
            results.push(CaseResult::new(
                "t1.emulator_start",
                Outcome::Fail,
                format!("argv build failed: {err}"),
            ));
            results.push(CaseResult::new(
                "t1.os_boot",
                Outcome::NotRun,
                "OS boot not attempted (argv failure)",
            ));
            return results;
        }
    };

    // Emulator-only: send monitor quit so a successful spawn can exit cleanly.
    let stdin = if cfg.is_emulator_only() {
        Some("quit\n")
    } else {
        None
    };

    let exec = run_argv_with_timeout(&argv, Duration::from_secs(cfg.timeout_secs), stdin);

    if let Some(err) = &exec.spawn_error {
        results.push(
            CaseResult::new(
                "t1.emulator_start",
                Outcome::Fail,
                "failed to spawn QEMU process",
            )
            .with_detail(err.clone()),
        );
    } else if exec.timed_out {
        // Spawn succeeded (process ran until kill) → emulator start capability demonstrated,
        // but treat timeout as FAIL for the smoke contract (should quit via monitor).
        results.push(
            CaseResult::new(
                "t1.emulator_start",
                Outcome::Fail,
                "QEMU spawned but did not exit before timeout",
            )
            .with_detail(format!(
                "accel={} duration_ms={} (process killed)",
                argv.accel_used.as_str(),
                exec.duration_ms
            )),
        );
    } else {
        // Process spawned and exited — emulator start OK. Non-zero exit can still mean
        // the binary ran (e.g. machine none quirks); we require spawn + no timeout.
        results.push(
            CaseResult::new(
                "t1.emulator_start",
                Outcome::Pass,
                "QEMU process started and exited within timeout",
            )
            .with_detail(format!(
                "accel={} exit_code={:?} duration_ms={}\nstderr_tail={}",
                argv.accel_used.as_str(),
                exec.exit_code,
                exec.duration_ms,
                trim_tail(&exec.stderr, 400)
            )),
        );
    }

    // Honest OS boot claim: Mission 003 has no authorized bootable Ryoku/system image.
    if cfg.is_emulator_only() {
        results.push(
            CaseResult::new(
                "t1.os_boot",
                Outcome::NotRun,
                "OS boot NOT claimed — emulator-only config (no disk/kernel)",
            )
            .with_detail(
                "Never claim Ryoku OS booted without a bootable kernel/system under test. \
                 Future missions may attach disposable images under tests/qemu/run/ only."
                    .to_string(),
            ),
        );
    } else {
        results.push(
            CaseResult::new(
                "t1.os_boot",
                Outcome::NotRun,
                "OS boot verification not implemented in Mission 003",
            )
            .with_detail(
                "Config references disk/kernel, but serial sentinel boot checks land in a later mission."
                    .to_string(),
            ),
        );
    }

    results
}

fn trim_tail(s: &str, max: usize) -> String {
    let t = s.trim();
    if t.len() <= max {
        t.to_string()
    } else {
        format!("…{}", &t[t.len() - max..])
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tools::ToolProbe;
    use std::collections::HashMap;
    use std::path::{Path, PathBuf};

    struct NoQemu;

    impl ToolProbe for NoQemu {
        fn version_line(&self, _program: &str, _args: &[&str]) -> Option<String> {
            None
        }
        fn path_exists(&self, _path: &Path) -> bool {
            false
        }
        fn path_readable(&self, _path: &Path) -> bool {
            false
        }
        fn path_writable(&self, _path: &Path) -> bool {
            false
        }
    }

    #[test]
    fn t1_skips_without_qemu() {
        let lab = PathBuf::from("/workspace/tests/qemu");
        let results = run_t1(&lab, &NoQemu);
        let emu = results
            .iter()
            .find(|r| r.id == "t1.emulator_start")
            .unwrap();
        let boot = results.iter().find(|r| r.id == "t1.os_boot").unwrap();
        assert_eq!(emu.outcome, Outcome::Skipped);
        assert_eq!(boot.outcome, Outcome::NotRun);
    }

    #[test]
    fn hashmap_probe_compiles_for_future_mocks() {
        let mut v: HashMap<String, String> = HashMap::new();
        v.insert("x".into(), "y".into());
        assert_eq!(v.get("x").map(String::as_str), Some("y"));
    }
}
