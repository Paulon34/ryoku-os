//! Orchestrates probes → findings → exit semantics.

use crate::check::run_all_checks;
use crate::finding::{Finding, Importance, Severity};
use crate::probe::FsProbe;
use crate::report::{format_report, worst_required_severity};
use crate::runner::CommandRunner;

/// Host diagnostic engine parameterized by command and filesystem probes.
#[derive(Debug, Default, Clone, Copy)]
pub struct Doctor;

impl Doctor {
    #[must_use]
    pub const fn new() -> Self {
        Self
    }

    /// Collect all findings without printing.
    pub fn diagnose<R: CommandRunner, F: FsProbe>(self, runner: &R, fs: &F) -> Vec<Finding> {
        run_all_checks(runner, fs)
    }

    /// Render a human-readable report.
    pub fn render_report(findings: &[Finding]) -> String {
        format_report(findings)
    }

    /// Process exit code: `1` if any **required** check is [`Severity::Fail`], else `0`.
    ///
    /// Optional WARNs (missing QEMU, KVM perms) do **not** fail the process.
    /// This keeps "doctor unhappy about VMs" separate from "Rust toolchain broken".
    #[must_use]
    pub fn exit_code(findings: &[Finding]) -> i32 {
        match worst_required_severity(findings) {
            Some(Severity::Fail) => 1,
            _ => 0,
        }
    }

    /// True when every required check is OK (WARNs on optional tools allowed).
    #[must_use]
    pub fn required_ok(findings: &[Finding]) -> bool {
        findings
            .iter()
            .filter(|f| f.importance == Importance::Required)
            .all(|f| f.severity == Severity::Ok)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::finding::{Finding, Importance, Severity};

    #[test]
    fn exit_code_ignores_optional_warn() {
        let findings = vec![
            Finding::new("rustc", "rustc", Severity::Ok, Importance::Required, "ok"),
            Finding::new(
                "qemu",
                "qemu",
                Severity::Warn,
                Importance::Optional,
                "missing",
            ),
        ];
        assert_eq!(Doctor::exit_code(&findings), 0);
        assert!(Doctor::required_ok(&findings));
    }

    #[test]
    fn exit_code_fails_on_required_fail() {
        let findings = vec![Finding::new(
            "cargo",
            "cargo",
            Severity::Fail,
            Importance::Required,
            "missing",
        )];
        assert_eq!(Doctor::exit_code(&findings), 1);
        assert!(!Doctor::required_ok(&findings));
    }
}
