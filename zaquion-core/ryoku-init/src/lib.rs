//! Ryoku Boot Seed — shared identity constants and helpers (Mission 008).
//!
//! This is a **prototype init**, not a finished Ryoku userland or product OS boot.
//! A future T3 QEMU run may PASS `t3.boot_seed` when the guest serial contains
//! [`BOOT_SEED_READY_MARKER`]. That is still **not** a full Ryoku OS product boot.

#![forbid(unsafe_code)]

/// Printed by `ryoku-init` as PID 1 on the guest console.
pub const PROCESS_IDENTITY: &str = "ryoku-init";

/// Stable serial marker for Virtual Lab T3 (must appear from the real guest process).
pub const BOOT_SEED_READY_MARKER: &str = "RYOKU_BOOT_SEED_READY";

/// Human-readable banner line (includes identity + marker).
#[must_use]
pub fn boot_banner(pid: u32) -> String {
    format!("{PROCESS_IDENTITY}: pid={pid} seed=mission-008\n{BOOT_SEED_READY_MARKER}\n")
}

/// True when serial text contains the required boot-seed marker (guest evidence).
#[must_use]
pub fn serial_has_boot_seed_marker(serial: &str) -> bool {
    serial.contains(BOOT_SEED_READY_MARKER)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn banner_includes_identity_and_marker() {
        let b = boot_banner(1);
        assert!(b.contains(PROCESS_IDENTITY));
        assert!(b.contains(BOOT_SEED_READY_MARKER));
        assert!(b.contains("pid=1"));
    }

    #[test]
    fn marker_detection_rejects_harness_noise_alone() {
        assert!(!serial_has_boot_seed_marker("QEMU monitor\n"));
        assert!(serial_has_boot_seed_marker(
            "ryoku-init: pid=1\nRYOKU_BOOT_SEED_READY\n"
        ));
    }
}
