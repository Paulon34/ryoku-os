//! Finding model: what the doctor reports for each check.

use std::fmt;

/// Outcome of a single diagnostic check.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Severity {
    /// Tool/path present and usable for its stated purpose.
    Ok,
    /// Usable with caveats, or an optional tool is missing.
    Warn,
    /// Required capability missing or unusable.
    Fail,
}

impl Severity {
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Ok => "OK",
            Self::Warn => "WARN",
            Self::Fail => "FAIL",
        }
    }
}

impl fmt::Display for Severity {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

/// Whether a check blocks a "healthy Zaquion build host" verdict.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Importance {
    /// Needed to compile/test Zaquion Core Rust today.
    Required,
    /// Useful later (QEMU harness, bindgen, kernel work) but not for `cargo build`.
    Optional,
}

impl Importance {
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Required => "required",
            Self::Optional => "optional",
        }
    }
}

impl fmt::Display for Importance {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

/// One row in the doctor report.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Finding {
    pub id: &'static str,
    pub title: &'static str,
    pub severity: Severity,
    pub importance: Importance,
    pub summary: String,
    pub detail: Option<String>,
}

impl Finding {
    #[must_use]
    pub fn new(
        id: &'static str,
        title: &'static str,
        severity: Severity,
        importance: Importance,
        summary: impl Into<String>,
    ) -> Self {
        Self {
            id,
            title,
            severity,
            importance,
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
