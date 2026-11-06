//! Human-readable Virtual Lab reports.

use crate::status::{CaseResult, Outcome};

/// Format T0/T1 results for stdout / log files under `tests/qemu/results/` (gitignored).
#[must_use]
pub fn format_lab_report(title: &str, results: &[CaseResult]) -> String {
    let mut out = String::new();
    out.push_str(title);
    out.push('\n');
    out.push_str(&"=".repeat(title.len()));
    out.push_str("\n\n");

    for case in results {
        out.push_str(&format!(
            "[{}] {} — {}\n",
            case.outcome.as_str(),
            case.id,
            case.summary
        ));
        if let Some(detail) = &case.detail {
            for line in detail.lines() {
                out.push_str(&format!("       {line}\n"));
            }
        }
        out.push('\n');
    }

    let pass = count(results, Outcome::Pass);
    let fail = count(results, Outcome::Fail);
    let skipped = count(results, Outcome::Skipped);
    let not_run = count(results, Outcome::NotRun);

    out.push_str("---\n");
    out.push_str(&format!(
        "Summary: {pass} PASS, {fail} FAIL, {skipped} SKIPPED, {not_run} NOT_RUN\n"
    ));
    if fail == 0 {
        out.push_str("Verdict: no FAIL — suite acceptable for CI without virt/KVM.\n");
    } else {
        out.push_str("Verdict: FAIL present — investigate before merge.\n");
    }
    out
}

fn count(results: &[CaseResult], outcome: Outcome) -> usize {
    results.iter().filter(|r| r.outcome == outcome).count()
}

/// Exit code: 1 if any FAIL, else 0 (SKIPPED/NOT_RUN are OK for CI).
#[must_use]
pub fn exit_code(results: &[CaseResult]) -> i32 {
    if results.iter().any(|r| r.outcome == Outcome::Fail) {
        1
    } else {
        0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn skipped_does_not_fail_exit() {
        let results = vec![
            CaseResult::new("a", Outcome::Pass, "ok"),
            CaseResult::new("b", Outcome::Skipped, "no qemu"),
            CaseResult::new("c", Outcome::NotRun, "no image"),
        ];
        assert_eq!(exit_code(&results), 0);
        let text = format_lab_report("test", &results);
        assert!(text.contains("SKIPPED"));
        assert!(text.contains("NOT_RUN"));
    }

    #[test]
    fn fail_sets_exit_1() {
        let results = vec![CaseResult::new("a", Outcome::Fail, "boom")];
        assert_eq!(exit_code(&results), 1);
    }
}
