//! Text report formatting and aggregation helpers.

use crate::finding::{Finding, Importance, Severity};

/// Worst severity among **required** findings (if any).
#[must_use]
pub fn worst_required_severity(findings: &[Finding]) -> Option<Severity> {
    findings
        .iter()
        .filter(|f| f.importance == Importance::Required)
        .map(|f| f.severity)
        .max()
}

/// Human-readable multi-line report (stdout for the CLI).
#[must_use]
pub fn format_report(findings: &[Finding]) -> String {
    let mut out = String::new();
    out.push_str("Ryoku Doctor — host diagnostics (read-only)\n");
    out.push_str("===========================================\n");
    out.push_str(
        "Checks never install packages, never use sudo, and never change permissions.\n\n",
    );

    for finding in findings {
        out.push_str(&format!(
            "[{}] {} ({}) — {}\n",
            finding.severity.as_str(),
            finding.title,
            finding.importance.as_str(),
            finding.summary
        ));
        if let Some(detail) = &finding.detail {
            for line in detail.lines() {
                out.push_str(&format!("       {line}\n"));
            }
        }
        out.push('\n');
    }

    let required_fail = findings
        .iter()
        .filter(|f| f.importance == Importance::Required && f.severity == Severity::Fail)
        .count();
    let warns = findings
        .iter()
        .filter(|f| f.severity == Severity::Warn)
        .count();
    let oks = findings
        .iter()
        .filter(|f| f.severity == Severity::Ok)
        .count();

    out.push_str("---\n");
    out.push_str(&format!(
        "Summary: {oks} OK, {warns} WARN, {required_fail} required FAIL\n"
    ));
    if required_fail == 0 {
        out.push_str(
            "Verdict: required toolchain looks usable for Zaquion Rust builds.\n\
             Optional WARNs (QEMU/KVM/etc.) do not block `cargo build` / `cargo test`.\n",
        );
    } else {
        out.push_str(
            "Verdict: required checks failed — fix the Rust/Cargo toolchain before building Zaquion.\n",
        );
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn report_mentions_read_only() {
        let findings = vec![Finding::new(
            "rustc",
            "Rust",
            Severity::Ok,
            Importance::Required,
            "rustc 1.83.0",
        )];
        let text = format_report(&findings);
        assert!(text.contains("read-only"));
        assert!(text.contains("[OK]"));
    }

    #[test]
    fn worst_required_prefers_fail() {
        let findings = vec![
            Finding::new("a", "a", Severity::Ok, Importance::Required, ""),
            Finding::new("b", "b", Severity::Fail, Importance::Required, ""),
            Finding::new("c", "c", Severity::Warn, Importance::Optional, ""),
        ];
        assert_eq!(worst_required_severity(&findings), Some(Severity::Fail));
    }
}
