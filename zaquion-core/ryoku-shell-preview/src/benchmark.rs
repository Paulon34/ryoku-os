//! Mission 016.2 — Controlled Performance benchmark (deterministic workload).
//!
//! Opt-in only (`RYOKU_CONTROLLED_BENCHMARK=1`). Off in normal interactive use.
//! Never invents numbers; never prefers a profile. QEMU TCG ≠ physical hardware.
//! Timing wrappers add measurable instrumentation cost — see docs.

use crate::{AdaptiveProfile, FrameSample};

/// Fixed workload sizes — identical for every profile under test.
pub const CONTROLLED_FULL_FRAMES: u32 = 24;
pub const CONTROLLED_BAND_FRAMES: u32 = 24;
/// Fixed band height for partial presents (rows).
pub const CONTROLLED_BAND_HEIGHT: u32 = 40;

/// One profile's collected samples from a controlled run.
#[derive(Debug, Clone, Default)]
pub struct ControlledProfileRun {
    pub selected: AdaptiveProfile,
    pub effective: AdaptiveProfile,
    pub full: Vec<FrameSample>,
    pub band: Vec<FrameSample>,
    pub scratch_bytes: usize,
}

impl ControlledProfileRun {
    #[must_use]
    pub fn new(selected: AdaptiveProfile) -> Self {
        Self {
            selected,
            effective: selected.effective(),
            full: Vec::with_capacity(CONTROLLED_FULL_FRAMES as usize),
            band: Vec::with_capacity(CONTROLLED_BAND_FRAMES as usize),
            scratch_bytes: 0,
        }
    }

    pub fn push_full(&mut self, sample: FrameSample) {
        self.scratch_bytes = sample.scratch_bytes;
        self.full.push(sample);
    }

    pub fn push_band(&mut self, sample: FrameSample) {
        self.scratch_bytes = sample.scratch_bytes;
        self.band.push(sample);
    }

    #[must_use]
    pub fn summary(&self) -> ControlledSummary {
        ControlledSummary::from_run(self)
    }
}

/// Aggregated mean / p95 for compose, present, total — plus frame counts / mem.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ControlledSummary {
    pub selected: AdaptiveProfile,
    pub effective: AdaptiveProfile,
    pub full_frames: u64,
    pub band_frames: u64,
    pub mean_compose_us: u64,
    pub mean_present_us: u64,
    pub mean_total_us: u64,
    pub p95_compose_us: u64,
    pub p95_present_us: u64,
    pub p95_total_us: u64,
    pub mean_full_total_us: u64,
    pub mean_band_total_us: u64,
    pub scratch_kib: u64,
}

impl ControlledSummary {
    #[must_use]
    pub fn from_run(run: &ControlledProfileRun) -> Self {
        let all: Vec<FrameSample> = run.full.iter().chain(run.band.iter()).copied().collect();
        let compose: Vec<u128> = all.iter().map(|s| s.compose.as_micros()).collect();
        let present: Vec<u128> = all.iter().map(|s| s.present.as_micros()).collect();
        let total: Vec<u128> = all.iter().map(|s| s.total().as_micros()).collect();
        let full_tot: Vec<u128> = run.full.iter().map(|s| s.total().as_micros()).collect();
        let band_tot: Vec<u128> = run.band.iter().map(|s| s.total().as_micros()).collect();
        Self {
            selected: run.selected,
            effective: run.effective,
            full_frames: run.full.len() as u64,
            band_frames: run.band.len() as u64,
            mean_compose_us: mean_us(&compose),
            mean_present_us: mean_us(&present),
            mean_total_us: mean_us(&total),
            p95_compose_us: percentile_us(&compose, 95),
            p95_present_us: percentile_us(&present, 95),
            p95_total_us: percentile_us(&total, 95),
            mean_full_total_us: mean_us(&full_tot),
            mean_band_total_us: mean_us(&band_tot),
            scratch_kib: (run.scratch_bytes / 1024) as u64,
        }
    }

    /// Serial one-liner (no invented fields).
    #[must_use]
    pub fn serial_line(&self) -> String {
        format!(
            "CONTROLLED {}->{} full={} band={} mean_c={}us mean_p={}us mean_t={}us \
             p95_c={}us p95_p={}us p95_t={}us mean_full_t={}us mean_band_t={}us mem={}KiB \
             COST_INSTRUMENTED=1 TCG_NE_HW=1",
            self.selected.name(),
            self.effective.name(),
            self.full_frames,
            self.band_frames,
            self.mean_compose_us,
            self.mean_present_us,
            self.mean_total_us,
            self.p95_compose_us,
            self.p95_present_us,
            self.p95_total_us,
            self.mean_full_total_us,
            self.mean_band_total_us,
            self.scratch_kib
        )
    }
}

/// Profiles exercised by the controlled harness (order fixed for determinism).
#[must_use]
pub fn controlled_profile_order() -> [AdaptiveProfile; 3] {
    [
        AdaptiveProfile::Lite,
        AdaptiveProfile::Balanced,
        AdaptiveProfile::Ultra,
    ]
}

/// Opt-in flag parser — off unless explicit 1/true.
#[must_use]
pub fn controlled_benchmark_enabled(flag: Option<&str>) -> bool {
    matches!(flag, Some("1") | Some("true") | Some("TRUE"))
}

/// Band `[y0, y1)` for partial presents — deterministic from FB height.
#[must_use]
pub fn controlled_band(height: u32) -> (u32, u32) {
    let h = CONTROLLED_BAND_HEIGHT.min(height.saturating_sub(1).max(1));
    let y0 = (height / 3).min(height.saturating_sub(h));
    (y0, y0 + h)
}

#[must_use]
pub fn mean_us(samples: &[u128]) -> u64 {
    if samples.is_empty() {
        return 0;
    }
    let sum: u128 = samples.iter().sum();
    (sum / samples.len() as u128) as u64
}

#[must_use]
pub fn percentile_us(samples: &[u128], pct: u8) -> u64 {
    if samples.is_empty() {
        return 0;
    }
    let mut v = samples.to_vec();
    v.sort_unstable();
    let pct = usize::from(pct).min(100);
    // Nearest-rank: ceil(pct/100 * n) - 1 (clamped).
    let rank = (pct * v.len()).div_ceil(100).max(1);
    let idx = rank.saturating_sub(1).min(v.len() - 1);
    v[idx] as u64
}

/// Documented instrumentation overhead note (not a measured claim).
#[must_use]
pub fn instrumentation_cost_note() -> &'static str {
    "COST_INSTRUMENTED: Instant wrappers around compose/present add timer + bookkeeping \
     overhead; do not treat deltas as pure paint cost. QEMU TCG ≠ physical hardware."
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    fn test_sample(
        selected: AdaptiveProfile,
        compose: Duration,
        present: Duration,
        full: bool,
        rows: u32,
        mem: usize,
    ) -> FrameSample {
        FrameSample::from_parts(selected, compose, present, rows, full, full, mem)
    }

    #[test]
    fn off_by_default() {
        assert!(!controlled_benchmark_enabled(None));
        assert!(!controlled_benchmark_enabled(Some("0")));
        assert!(controlled_benchmark_enabled(Some("1")));
    }

    #[test]
    fn workload_sizes_identical_constants() {
        assert_eq!(CONTROLLED_FULL_FRAMES, 24);
        assert_eq!(CONTROLLED_BAND_FRAMES, 24);
        assert_eq!(controlled_profile_order().len(), 3);
    }

    #[test]
    fn ultra_effective_balanced_in_summary() {
        let mut run = ControlledProfileRun::new(AdaptiveProfile::Ultra);
        for _ in 0..3 {
            run.push_full(test_sample(
                AdaptiveProfile::Ultra,
                Duration::from_micros(100),
                Duration::from_micros(50),
                true,
                240,
                4096,
            ));
        }
        for _ in 0..3 {
            run.push_band(test_sample(
                AdaptiveProfile::Ultra,
                Duration::from_micros(40),
                Duration::from_micros(20),
                false,
                40,
                4096,
            ));
        }
        let s = run.summary();
        assert_eq!(s.selected, AdaptiveProfile::Ultra);
        assert_eq!(s.effective, AdaptiveProfile::Balanced);
        assert_eq!(s.full_frames, 3);
        assert_eq!(s.band_frames, 3);
        assert_eq!(s.mean_compose_us, 70);
        assert!(s.serial_line().contains("ULTRA->BALANCED"));
        assert!(s.serial_line().contains("COST_INSTRUMENTED=1"));
        assert!(s.serial_line().contains("TCG_NE_HW=1"));
    }

    #[test]
    fn p95_and_mean_from_supplied_samples_only() {
        let samples = [10u128, 20, 30, 40, 100];
        assert_eq!(mean_us(&samples), 40);
        assert_eq!(percentile_us(&samples, 95), 100);
        assert_eq!(percentile_us(&samples, 0), 10);
    }

    #[test]
    fn band_deterministic() {
        assert_eq!(controlled_band(300), (100, 140));
        let (a, b) = controlled_band(50);
        assert!(b > a);
        assert!(b <= 50);
    }

    #[test]
    fn identical_workload_across_profiles_structure() {
        // Same push counts → same frame tallies regardless of profile label.
        for p in controlled_profile_order() {
            let mut run = ControlledProfileRun::new(p);
            for _ in 0..CONTROLLED_FULL_FRAMES {
                run.push_full(test_sample(
                    p,
                    Duration::from_micros(1),
                    Duration::from_micros(1),
                    true,
                    10,
                    100,
                ));
            }
            for _ in 0..CONTROLLED_BAND_FRAMES {
                run.push_band(test_sample(
                    p,
                    Duration::from_micros(1),
                    Duration::from_micros(1),
                    false,
                    10,
                    100,
                ));
            }
            let s = run.summary();
            assert_eq!(s.full_frames, u64::from(CONTROLLED_FULL_FRAMES));
            assert_eq!(s.band_frames, u64::from(CONTROLLED_BAND_FRAMES));
            assert_eq!(s.effective, p.effective());
        }
    }

    #[test]
    fn instrumentation_note_mentions_tcg() {
        let n = instrumentation_cost_note();
        assert!(n.contains("TCG"));
        assert!(n.contains("COST_INSTRUMENTED"));
        assert!(!n.contains("blur"));
    }
}
