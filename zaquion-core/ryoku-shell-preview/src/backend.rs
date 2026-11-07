//! Mission 020 — Display / compositor / input backend abstraction.
//!
//! Default path: fbdev (Mission 014.2 / 015.2.1). DRM/KMS is a **study + safe
//! stub** that always falls back to fbdev unless explicitly enabled and proven.
//! Wayland is **architecture/docs only** — this module never claims a Wayland
//! compositor.

use crate::Rect;

/// Which present backend is active (honesty labels for serial/docs).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum DisplayBackendKind {
    #[default]
    Fbdev,
    /// Not activated by default — requires future safe probe + fallback.
    DrmKmsFallbackFb,
}

impl DisplayBackendKind {
    #[must_use]
    pub fn name(self) -> &'static str {
        match self {
            Self::Fbdev => "FBDEV",
            Self::DrmKmsFallbackFb => "DRM_KMS_FALLBACK_FB",
        }
    }

    /// Parse allowlisted env `RYOKU_DISPLAY_BACKEND`.
    #[must_use]
    pub fn parse(s: &str) -> Option<Self> {
        match s.trim().to_ascii_lowercase().as_str() {
            "fb" | "fbdev" | "framebuffer" => Some(Self::Fbdev),
            // Explicit request only — still falls back to fbdev at runtime today.
            "drm" | "kms" | "drm-kms" => Some(Self::DrmKmsFallbackFb),
            _ => None,
        }
    }
}

/// Result of selecting a backend (always usable fbdev path today).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DisplayBackendSelection {
    pub requested: DisplayBackendKind,
    pub active: DisplayBackendKind,
    pub fell_back: bool,
}

impl DisplayBackendSelection {
    /// Safe selection: DRM request → note fallback to fbdev (no unsafe DRM ioctls yet).
    #[must_use]
    pub fn resolve(requested: DisplayBackendKind) -> Self {
        match requested {
            DisplayBackendKind::Fbdev => Self {
                requested,
                active: DisplayBackendKind::Fbdev,
                fell_back: false,
            },
            DisplayBackendKind::DrmKmsFallbackFb => Self {
                requested,
                active: DisplayBackendKind::Fbdev,
                fell_back: true,
            },
        }
    }

    #[must_use]
    pub fn serial_line(self) -> String {
        if self.fell_back {
            format!(
                "DISPLAY requested={} active={} FALLBACK=1 (DRM/KMS study only — fbdev present)",
                self.requested.name(),
                self.active.name()
            )
        } else {
            format!(
                "DISPLAY requested={} active={} FALLBACK=0",
                self.requested.name(),
                self.active.name()
            )
        }
    }
}

/// Compositor surface abstract (software buffer damage) — not a Wayland surface.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct DamageRegion {
    pub rect: Rect,
}

/// Input backend kind (guest evdev today).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum InputBackendKind {
    #[default]
    GuestEvdev,
}

impl InputBackendKind {
    #[must_use]
    pub fn name(self) -> &'static str {
        match self {
            Self::GuestEvdev => "GUEST_EVDEV",
        }
    }
}

/// Architecture note: Wayland is out of scope for runtime.
#[must_use]
pub fn wayland_runtime_status() -> &'static str {
    "WAYLAND=ARCH_ONLY — not a Wayland compositor; see RYOKU_DESKTOP_ARCHITECTURE.md"
}

/// DRM/KMS study summary (safe prototype = fallback path only in this mission).
#[must_use]
pub fn drm_kms_study_note() -> &'static str {
    "DRM/KMS: studied for future modeset; Mission 020 provides selection + forced \
     fbdev fallback only. No modeset ioctls; no claim of working DRM present."
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_is_fbdev_no_fallback() {
        let s = DisplayBackendSelection::resolve(DisplayBackendKind::Fbdev);
        assert_eq!(s.active, DisplayBackendKind::Fbdev);
        assert!(!s.fell_back);
    }

    #[test]
    fn drm_request_falls_back_to_fbdev() {
        let s = DisplayBackendSelection::resolve(DisplayBackendKind::DrmKmsFallbackFb);
        assert_eq!(s.active, DisplayBackendKind::Fbdev);
        assert!(s.fell_back);
        assert!(s.serial_line().contains("FALLBACK=1"));
    }

    #[test]
    fn wayland_not_claimed_as_runtime() {
        let n = wayland_runtime_status();
        assert!(n.contains("ARCH_ONLY"));
        assert!(!n.contains("compositor running"));
    }

    #[test]
    fn parse_allowlist() {
        assert_eq!(
            DisplayBackendKind::parse("fbdev"),
            Some(DisplayBackendKind::Fbdev)
        );
        assert_eq!(
            DisplayBackendKind::parse("drm"),
            Some(DisplayBackendKind::DrmKmsFallbackFb)
        );
        assert_eq!(DisplayBackendKind::parse("wayland"), None);
    }
}
