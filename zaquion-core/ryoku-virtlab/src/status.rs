//! Strict harness outcomes: PASS / FAIL / SKIPPED / NOT_RUN.

use std::fmt;

/// Final status for one lab case.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Outcome {
    /// Case ran and met its criteria.
    Pass,
    /// Case ran and failed its criteria (or validation failed when required).
    Fail,
    /// Intentionally not executed (e.g. QEMU absent for T1 emulator smoke).
    Skipped,
    /// Preconditions missing for a stronger claim (e.g. no guest image → OS boot NOT_RUN).
    NotRun,
}

impl Outcome {
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Pass => "PASS",
            Self::Fail => "FAIL",
            Self::Skipped => "SKIPPED",
            Self::NotRun => "NOT_RUN",
        }
    }
}

impl fmt::Display for Outcome {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

/// One named result row for reports and CI.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CaseResult {
    pub id: String,
    pub outcome: Outcome,
    pub summary: String,
    pub detail: Option<String>,
}

impl CaseResult {
    #[must_use]
    pub fn new(id: impl Into<String>, outcome: Outcome, summary: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            outcome,
            summary: summary.into(),
            detail: None,
        }
    }

    #[must_use]
    pub fn with_detail(mut self, detail: impl Into<String>) -> Self {
        self.detail = Some(detail.into());
        self
    }
}
