//! Mission 018 — Internal allowlisted apps (Launcher → WindowManager).
//!
//! No arbitrary exec. No Bash. No external binaries. Ultra paint still falls
//! back to Balanced via AdaptiveProfile::effective().

use crate::{WindowKind, LAUNCHER_CATEGORIES};

/// Allowlisted internal app ids (subset of WindowKind).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InternalApp {
    About,
    SystemMonitor,
    Settings,
    FilesRo,
}

impl InternalApp {
    #[must_use]
    pub fn kind(self) -> WindowKind {
        match self {
            Self::About => WindowKind::About,
            Self::SystemMonitor => WindowKind::SystemMonitor,
            Self::Settings => WindowKind::Settings,
            Self::FilesRo => WindowKind::FilesRo,
        }
    }

    #[must_use]
    pub fn name(self) -> &'static str {
        self.kind().title()
    }

    /// Map launcher category index → allowlisted app (or None for Demo-only).
    #[must_use]
    pub fn from_launcher_category(idx: usize) -> Option<Self> {
        match idx {
            0 => Some(Self::About),         // SYSTEM
            1 => Some(Self::SystemMonitor), // DEV TOOLS
            2 => Some(Self::FilesRo),       // FILES
            3 => Some(Self::Settings),      // SETTINGS
            _ => None,
        }
    }

    #[must_use]
    pub fn body_lines(self) -> [&'static str; 3] {
        match self {
            Self::About => [
                "RYOKU MINIMAL LAB SHELL",
                "NOT A PRODUCT OS BOOT",
                "NO WAYLAND / NO BLUR / NO 3D",
            ],
            Self::SystemMonitor => [
                "ILLUSTRATIVE METRICS ONLY",
                "NO /PROC LIVE PROBES HERE",
                "SEE HW CONSOLE FOR FACTS",
            ],
            Self::Settings => [
                "PROFILE VIA F1 F2 F3",
                "NO PERSISTENCE STORE",
                "ULTRA = ARCH FALLBACK",
            ],
            Self::FilesRo => [
                "READ-ONLY FILE LIST DEMO",
                "/bin /dev /proc ILLUSTRATIVE",
                "NO EXEC / NO WRITE",
            ],
        }
    }
}

/// Every launcher category must resolve to an allowlisted app.
#[must_use]
pub fn launcher_allowlist_complete() -> bool {
    (0..LAUNCHER_CATEGORIES.len()).all(|i| InternalApp::from_launcher_category(i).is_some())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn allowlist_covers_all_launcher_categories() {
        assert!(launcher_allowlist_complete());
        assert_eq!(
            InternalApp::from_launcher_category(0).unwrap().kind(),
            WindowKind::About
        );
        assert_eq!(
            InternalApp::from_launcher_category(2).unwrap().kind(),
            WindowKind::FilesRo
        );
    }

    #[test]
    fn honesty_no_exec_in_copy() {
        for app in [
            InternalApp::About,
            InternalApp::SystemMonitor,
            InternalApp::Settings,
            InternalApp::FilesRo,
        ] {
            for line in app.body_lines() {
                assert!(!line.contains("exec "), "{line}");
            }
            assert!(app.kind().allowlisted());
        }
    }
}
