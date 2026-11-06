//! Process execution with timeouts (stdlib only; no shell).

use std::io::{Read, Write};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

use crate::argv::QemuArgv;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExecResult {
    pub timed_out: bool,
    pub exit_code: Option<i32>,
    pub stdout: String,
    pub stderr: String,
    pub spawn_error: Option<String>,
    pub duration_ms: u128,
}

impl ExecResult {
    #[must_use]
    pub fn spawned(&self) -> bool {
        self.spawn_error.is_none()
    }
}

/// Spawn argv with optional stdin payload; kill on timeout.
pub fn run_argv_with_timeout(
    argv: &QemuArgv,
    timeout: Duration,
    stdin_payload: Option<&str>,
) -> ExecResult {
    let started = Instant::now();
    let mut cmd = Command::new(&argv.program);
    cmd.args(&argv.args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

    let mut child = match cmd.spawn() {
        Ok(child) => child,
        Err(err) => {
            return ExecResult {
                timed_out: false,
                exit_code: None,
                stdout: String::new(),
                stderr: String::new(),
                spawn_error: Some(format!("{}: {err}", argv.program)),
                duration_ms: started.elapsed().as_millis(),
            };
        }
    };

    if let Some(payload) = stdin_payload {
        if let Some(mut stdin) = child.stdin.take() {
            let _ = stdin.write_all(payload.as_bytes());
        }
    } else {
        drop(child.stdin.take());
    }

    let mut stdout_pipe = child.stdout.take();
    let mut stderr_pipe = child.stderr.take();

    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                let mut stdout_buf = Vec::new();
                let mut stderr_buf = Vec::new();
                if let Some(ref mut out) = stdout_pipe {
                    let _ = out.read_to_end(&mut stdout_buf);
                }
                if let Some(ref mut err) = stderr_pipe {
                    let _ = err.read_to_end(&mut stderr_buf);
                }
                return ExecResult {
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
                    let _ = child.kill();
                    let _ = child.wait();
                    let mut stdout_buf = Vec::new();
                    let mut stderr_buf = Vec::new();
                    if let Some(ref mut out) = stdout_pipe {
                        let _ = out.read_to_end(&mut stdout_buf);
                    }
                    if let Some(ref mut err) = stderr_pipe {
                        let _ = err.read_to_end(&mut stderr_buf);
                    }
                    return ExecResult {
                        timed_out: true,
                        exit_code: None,
                        stdout: String::from_utf8_lossy(&stdout_buf).into_owned(),
                        stderr: String::from_utf8_lossy(&stderr_buf).into_owned(),
                        spawn_error: None,
                        duration_ms: started.elapsed().as_millis(),
                    };
                }
                thread::sleep(Duration::from_millis(20));
            }
            Err(err) => {
                return ExecResult {
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tools::AccelChoice;

    #[test]
    fn true_exits_quickly() {
        let argv = QemuArgv {
            program: "true".into(),
            args: vec![],
            accel_used: AccelChoice::Tcg,
        };
        let result = run_argv_with_timeout(&argv, Duration::from_secs(2), None);
        assert!(result.spawned());
        assert!(!result.timed_out);
        assert_eq!(result.exit_code, Some(0));
    }

    #[test]
    fn timeout_kills_sleep() {
        let argv = QemuArgv {
            program: "sleep".into(),
            args: vec!["5".into()],
            accel_used: AccelChoice::Tcg,
        };
        let result = run_argv_with_timeout(&argv, Duration::from_millis(200), None);
        assert!(result.spawned());
        assert!(result.timed_out);
    }

    #[test]
    fn missing_binary_reports_spawn_error() {
        let argv = QemuArgv {
            program: "ryoku-virtlab-definitely-missing-binary".into(),
            args: vec![],
            accel_used: AccelChoice::Tcg,
        };
        let result = run_argv_with_timeout(&argv, Duration::from_secs(1), None);
        assert!(!result.spawned());
        assert!(result.spawn_error.is_some());
    }
}
