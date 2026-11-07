//! Mission 016.1 — Adaptive Performance instrumentation.
//!
//! Host-side helpers only. Never invent guest timings or `PASS_MANUAL`.
//! QEMU TCG timings are **not** hardware measurements.

use crate::AdaptiveProfile;
use std::time::Duration;

/// One compose→present sample (selected vs effective profile recorded).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FrameSample {
    pub selected: AdaptiveProfile,
    pub effective: AdaptiveProfile,
    pub compose: Duration,
    pub present: Duration,
    /// Rows blitted (`height` means full frame).
    pub rows_blitted: u32,
    pub full_frame: bool,
    pub flushed: bool,
    /// Approximate scratch pixel bytes (RGB888).
    pub scratch_bytes: usize,
}

impl FrameSample {
    #[must_use]
    pub fn total(self) -> Duration {
        self.compose.saturating_add(self.present)
    }

    #[must_use]
    pub fn from_parts(
        selected: AdaptiveProfile,
        compose: Duration,
        present: Duration,
        rows_blitted: u32,
        full_frame: bool,
        flushed: bool,
        scratch_bytes: usize,
    ) -> Self {
        Self {
            selected,
            effective: selected.effective(),
            compose,
            present,
            rows_blitted,
            full_frame,
            flushed,
            scratch_bytes,
        }
    }
}

/// Accumulator for serial metrics (approx latency / redraw count / mem).
#[derive(Debug, Clone, Default)]
pub struct FrameAccumulator {
    pub frames: u64,
    pub full_frames: u64,
    pub band_frames: u64,
    pub compose_ns: u128,
    pub present_ns: u128,
    pub rows_blitted: u64,
    pub scratch_bytes: usize,
    pub selected: AdaptiveProfile,
    pub effective: AdaptiveProfile,
}

impl FrameAccumulator {
    pub fn note(&mut self, sample: FrameSample) {
        self.frames = self.frames.saturating_add(1);
        if sample.full_frame {
            self.full_frames = self.full_frames.saturating_add(1);
        } else {
            self.band_frames = self.band_frames.saturating_add(1);
        }
        self.compose_ns = self.compose_ns.saturating_add(sample.compose.as_nanos());
        self.present_ns = self.present_ns.saturating_add(sample.present.as_nanos());
        self.rows_blitted = self
            .rows_blitted
            .saturating_add(u64::from(sample.rows_blitted));
        self.scratch_bytes = sample.scratch_bytes;
        self.selected = sample.selected;
        self.effective = sample.effective;
    }

    #[must_use]
    pub fn avg_compose(&self) -> Option<Duration> {
        if self.frames == 0 {
            return None;
        }
        Some(Duration::from_nanos(
            (self.compose_ns / u128::from(self.frames)) as u64,
        ))
    }

    #[must_use]
    pub fn avg_present(&self) -> Option<Duration> {
        if self.frames == 0 {
            return None;
        }
        Some(Duration::from_nanos(
            (self.present_ns / u128::from(self.frames)) as u64,
        ))
    }

    #[must_use]
    pub fn avg_total_latency(&self) -> Option<Duration> {
        match (self.avg_compose(), self.avg_present()) {
            (Some(c), Some(p)) => Some(c.saturating_add(p)),
            _ => None,
        }
    }

    pub fn reset_window(&mut self) {
        self.frames = 0;
        self.full_frames = 0;
        self.band_frames = 0;
        self.compose_ns = 0;
        self.present_ns = 0;
        self.rows_blitted = 0;
    }

    /// Compact overlay / log line (ASCII). Does not invent numbers beyond samples.
    #[must_use]
    pub fn summary_line(&self) -> String {
        let c = self.avg_compose().map(|d| d.as_micros()).unwrap_or(0);
        let p = self.avg_present().map(|d| d.as_micros()).unwrap_or(0);
        format!(
            "PERF {}->{} n={} full={} band={} c={}us p={}us mem={}KiB",
            self.selected.name(),
            self.effective.name(),
            self.frames,
            self.full_frames,
            self.band_frames,
            c,
            p,
            self.scratch_bytes / 1024
        )
    }
}

/// Host-only comparison of two profile windows (caller supplies measured samples).
/// Never fabricates guest timings.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ProfileCompare {
    pub lite_avg_total: Duration,
    pub balanced_avg_total: Duration,
}

impl ProfileCompare {
    #[must_use]
    pub fn from_avgs(lite: Duration, balanced: Duration) -> Self {
        Self {
            lite_avg_total: lite,
            balanced_avg_total: balanced,
        }
    }

    /// True when Balanced average total exceeds Lite (same host harness).
    #[must_use]
    pub fn balanced_slower_than_lite(self) -> bool {
        self.balanced_avg_total > self.lite_avg_total
    }

    /// Ultra paint path equals Balanced (`effective()`); selected Ultra must not
    /// claim a distinct render cost beyond Balanced.
    #[must_use]
    pub fn ultra_paint_equals_balanced(
        selected_ultra_avg: Duration,
        balanced_avg: Duration,
    ) -> bool {
        selected_ultra_avg == balanced_avg
    }
}

/// Optional on-screen overlay — **off by default**.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct PerfOverlayPolicy {
    pub enabled: bool,
}

impl PerfOverlayPolicy {
    #[must_use]
    pub fn from_env_flag(flag: Option<&str>) -> Self {
        Self {
            enabled: matches!(flag, Some("1") | Some("true") | Some("TRUE")),
        }
    }
}

/// Investigation note: Ultra perceived slowdown under QEMU TCG.
#[must_use]
pub fn ultra_slowdown_investigation() -> &'static str {
    "Ultra selected paint/render falls back to Balanced (effective=BALANCED). \
     Perceived Ultra slowdown vs Lite is expected gradient/card cost shared with Balanced; \
     vs Balanced should be ~same paint path. QEMU TCG ≠ hardware; do not invent numbers."
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn selected_vs_effective_ultra() {
        let s = FrameSample::from_parts(
            AdaptiveProfile::Ultra,
            Duration::from_micros(100),
            Duration::from_micros(50),
            474,
            true,
            false,
            941 * 474 * 3,
        );
        assert_eq!(s.selected, AdaptiveProfile::Ultra);
        assert_eq!(s.effective, AdaptiveProfile::Balanced);
    }

    #[test]
    fn accumulator_avgs_and_summary() {
        let mut acc = FrameAccumulator::default();
        acc.note(FrameSample::from_parts(
            AdaptiveProfile::Lite,
            Duration::from_micros(200),
            Duration::from_micros(100),
            40,
            false,
            false,
            1024,
        ));
        acc.note(FrameSample::from_parts(
            AdaptiveProfile::Lite,
            Duration::from_micros(100),
            Duration::from_micros(50),
            40,
            false,
            false,
            1024,
        ));
        assert_eq!(acc.frames, 2);
        assert_eq!(acc.band_frames, 2);
        assert_eq!(acc.avg_compose().unwrap().as_micros(), 150);
        assert_eq!(acc.avg_present().unwrap().as_micros(), 75);
        assert!(acc.summary_line().contains("LITE->LITE"));
        assert!(acc.summary_line().contains("mem=1KiB"));
    }

    #[test]
    fn lite_vs_balanced_compare_uses_supplied_samples_only() {
        let cmp = ProfileCompare::from_avgs(Duration::from_micros(100), Duration::from_micros(250));
        assert!(cmp.balanced_slower_than_lite());
        // Ultra paint equals Balanced when harness feeds equal avgs.
        assert!(ProfileCompare::ultra_paint_equals_balanced(
            Duration::from_micros(250),
            Duration::from_micros(250),
        ));
    }

    #[test]
    fn overlay_off_by_default() {
        assert!(!PerfOverlayPolicy::default().enabled);
        assert!(!PerfOverlayPolicy::from_env_flag(None).enabled);
        assert!(!PerfOverlayPolicy::from_env_flag(Some("0")).enabled);
        assert!(PerfOverlayPolicy::from_env_flag(Some("1")).enabled);
    }

    #[test]
    fn ultra_investigation_mentions_fallback_and_tcg() {
        let n = ultra_slowdown_investigation();
        assert!(n.contains("Balanced"));
        assert!(n.contains("TCG"));
        assert!(!n.contains("blur"));
    }
}
