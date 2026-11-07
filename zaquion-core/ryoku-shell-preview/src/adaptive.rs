//! Mission 016 — Adaptive Desktop Foundation (Lite / Balanced / Ultra).
//!
//! Profiles control theme, layout density, animation **policy**, and render
//! policy. **Ultra is architecture-only**: paint falls back to Balanced; we
//! never fake blur / transparency / 3D / compositor / full Wayland.

use crate::{
    COLOR_DOCK, COLOR_MUTED, COLOR_NAVY, COLOR_NAVY_DEEP, COLOR_PANEL, COLOR_TEAL, COLOR_TEAL_DIM,
    COLOR_TEXT,
};

/// Session desktop profile (Mission 016).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum AdaptiveProfile {
    Lite,
    #[default]
    Balanced,
    /// Architecture stub — paint/render fall back to Balanced.
    Ultra,
}

impl AdaptiveProfile {
    #[must_use]
    pub fn parse(s: &str) -> Option<Self> {
        match s.trim().to_ascii_lowercase().as_str() {
            "lite" | "l" => Some(Self::Lite),
            "balanced" | "bal" | "b" => Some(Self::Balanced),
            "ultra" | "u" => Some(Self::Ultra),
            _ => None,
        }
    }

    #[must_use]
    pub fn name(self) -> &'static str {
        match self {
            Self::Lite => "LITE",
            Self::Balanced => "BALANCED",
            Self::Ultra => "ULTRA",
        }
    }

    #[must_use]
    pub fn panel_tag(self) -> &'static str {
        match self {
            Self::Lite => "PROFILE LITE",
            Self::Balanced => "PROFILE BALANCED",
            Self::Ultra => "ULTRA ARCH ONLY",
        }
    }

    /// Profile used for actual paint/render (Ultra → Balanced fallback).
    #[must_use]
    pub fn effective(self) -> Self {
        match self {
            Self::Ultra => Self::Balanced,
            other => other,
        }
    }

    #[must_use]
    pub fn target_fps(self) -> u32 {
        match self.effective() {
            Self::Lite => 20,
            Self::Balanced => 30,
            Self::Ultra => 30, // unreachable via effective()
        }
    }

    #[must_use]
    pub fn use_gradient_wallpaper(self) -> bool {
        !matches!(self.effective(), Self::Lite)
    }

    #[must_use]
    pub fn show_hint_card(self) -> bool {
        matches!(self.effective(), Self::Balanced)
    }

    /// Animation policy label (honesty — no real blur/fade on fbdev).
    #[must_use]
    pub fn animation_policy(self) -> &'static str {
        match self {
            Self::Lite => "ANIM NONE",
            Self::Balanced => "ANIM POLICY SIMPLE",
            Self::Ultra => "ANIM ARCH ONLY",
        }
    }

    #[must_use]
    pub fn theme(self) -> ProfileTheme {
        match self.effective() {
            Self::Lite => ProfileTheme {
                navy: (0x0c, 0x14, 0x22),
                navy_deep: (0x08, 0x0e, 0x16),
                teal: (0x4a, 0xa8, 0x98),
                teal_dim: (0x2a, 0x60, 0x58),
                panel: (0x12, 0x1c, 0x28),
                text: COLOR_TEXT,
                muted: (0x70, 0x80, 0x90),
                dock: (0x14, 0x1e, 0x2a),
            },
            Self::Balanced | Self::Ultra => ProfileTheme {
                navy: COLOR_NAVY,
                navy_deep: COLOR_NAVY_DEEP,
                teal: COLOR_TEAL,
                teal_dim: COLOR_TEAL_DIM,
                panel: COLOR_PANEL,
                text: COLOR_TEXT,
                muted: COLOR_MUTED,
                dock: COLOR_DOCK,
            },
        }
    }

    #[must_use]
    pub fn cycle_next(self) -> Self {
        match self {
            Self::Lite => Self::Balanced,
            Self::Balanced => Self::Ultra,
            Self::Ultra => Self::Lite,
        }
    }
}

/// Theme palette for a paint-effective profile.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ProfileTheme {
    pub navy: (u8, u8, u8),
    pub navy_deep: (u8, u8, u8),
    pub teal: (u8, u8, u8),
    pub teal_dim: (u8, u8, u8),
    pub panel: (u8, u8, u8),
    pub text: (u8, u8, u8),
    pub muted: (u8, u8, u8),
    pub dock: (u8, u8, u8),
}

/// Render/memory policy knobs (no continuous redraw; no visible fb clear).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RenderPolicy {
    pub target_fps: u32,
    pub dirty_rows_only: bool,
    pub allow_continuous_redraw: bool,
}

impl AdaptiveProfile {
    #[must_use]
    pub fn render_policy(self) -> RenderPolicy {
        RenderPolicy {
            target_fps: self.target_fps(),
            dirty_rows_only: true,
            allow_continuous_redraw: false,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ultra_falls_back_to_balanced_paint() {
        assert_eq!(
            AdaptiveProfile::Ultra.effective(),
            AdaptiveProfile::Balanced
        );
        assert_eq!(
            AdaptiveProfile::Ultra.theme(),
            AdaptiveProfile::Balanced.theme()
        );
        assert!(AdaptiveProfile::Ultra.panel_tag().contains("ARCH"));
    }

    #[test]
    fn lite_is_flatter() {
        assert!(!AdaptiveProfile::Lite.use_gradient_wallpaper());
        assert!(!AdaptiveProfile::Lite.show_hint_card());
        assert_eq!(AdaptiveProfile::Lite.target_fps(), 20);
    }

    #[test]
    fn parse_and_cycle() {
        assert_eq!(AdaptiveProfile::parse("lite"), Some(AdaptiveProfile::Lite));
        assert_eq!(
            AdaptiveProfile::parse("ULTRA"),
            Some(AdaptiveProfile::Ultra)
        );
        assert_eq!(
            AdaptiveProfile::Lite.cycle_next(),
            AdaptiveProfile::Balanced
        );
        assert_eq!(AdaptiveProfile::Ultra.cycle_next(), AdaptiveProfile::Lite);
    }

    #[test]
    fn no_continuous_redraw_policy() {
        for p in [
            AdaptiveProfile::Lite,
            AdaptiveProfile::Balanced,
            AdaptiveProfile::Ultra,
        ] {
            assert!(!p.render_policy().allow_continuous_redraw);
            assert!(p.render_policy().dirty_rows_only);
        }
    }

    #[test]
    fn honesty_no_blur_claim_in_names() {
        for p in [
            AdaptiveProfile::Lite,
            AdaptiveProfile::Balanced,
            AdaptiveProfile::Ultra,
        ] {
            assert!(!p.name().contains("BLUR"));
            assert!(!p.animation_policy().contains("BLUR"));
        }
    }
}
