//! Ryoku Boot Seed — shared identity constants and helpers (Mission 008 / 008.5).
//!
//! This is a **prototype init**, not a finished Ryoku userland or product OS boot.
//! A future T3 QEMU run may PASS `t3.boot_seed` when the guest serial contains
//! both [`PID1_IDENTITY_MARKER`] and [`BOOT_SEED_READY_MARKER`] from a real PID 1
//! process. That is still **not** a full Ryoku OS product boot.

#![forbid(unsafe_code)]

/// Printed by `ryoku-init` as process identity.
pub const PROCESS_IDENTITY: &str = "ryoku-init";

/// Stable serial marker for Virtual Lab T3 — emitted **only** when running as PID 1.
pub const BOOT_SEED_READY_MARKER: &str = "RYOKU_BOOT_SEED_READY";

/// Identity line substring required on guest serial for T3 PASS (`ryoku-init: pid=1`).
pub const PID1_IDENTITY_MARKER: &str = "ryoku-init: pid=1";

/// True when `pid` is the init process id.
#[must_use]
pub fn is_pid1(pid: u32) -> bool {
    pid == 1
}

/// Identity line including pid (always printed; READY is separate).
#[must_use]
pub fn identity_line(pid: u32) -> String {
    format!("{PROCESS_IDENTITY}: pid={pid} seed=mission-008")
}

/// Console output for a given pid.
///
/// - PID 1: identity + [`BOOT_SEED_READY_MARKER`]
/// - Otherwise: identity + diagnostic; **no** READY marker
#[must_use]
pub fn boot_output(pid: u32) -> String {
    let id = identity_line(pid);
    if is_pid1(pid) {
        format!("{id}\n{BOOT_SEED_READY_MARKER}\n")
    } else {
        format!("{id}\n{PROCESS_IDENTITY}: refusing READY marker (not PID 1; got pid={pid})\n")
    }
}

/// Legacy helper: banner only when PID 1 (includes READY). Prefer [`boot_output`].
#[must_use]
pub fn boot_banner(pid: u32) -> String {
    boot_output(pid)
}

/// True when serial text contains the READY marker (evidence fragment only).
#[must_use]
pub fn serial_has_boot_seed_marker(serial: &str) -> bool {
    serial.contains(BOOT_SEED_READY_MARKER)
}

/// True when serial has both PID 1 identity and READY (T3 PASS eligibility inputs).
#[must_use]
pub fn serial_has_pid1_boot_seed(serial: &str) -> bool {
    serial.contains(PID1_IDENTITY_MARKER) && serial.contains(BOOT_SEED_READY_MARKER)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pid1_emits_ready_and_identity() {
        let out = boot_output(1);
        assert!(out.contains(PID1_IDENTITY_MARKER));
        assert!(out.contains(BOOT_SEED_READY_MARKER));
        assert!(is_pid1(1));
        assert!(serial_has_pid1_boot_seed(&out));
    }

    #[test]
    fn non_pid1_omits_ready_marker() {
        for pid in [0u32, 2, 42, 9999] {
            let out = boot_output(pid);
            assert!(
                !out.contains(BOOT_SEED_READY_MARKER),
                "pid={pid} must not emit READY"
            );
            assert!(out.contains(&format!("pid={pid}")));
            assert!(out.contains("refusing READY marker"));
            assert!(!is_pid1(pid));
            assert!(!serial_has_pid1_boot_seed(&out));
        }
    }

    #[test]
    fn marker_detection_rejects_harness_noise_alone() {
        assert!(!serial_has_boot_seed_marker("QEMU monitor\n"));
        assert!(!serial_has_pid1_boot_seed(
            "QEMU monitor\nRYOKU_BOOT_SEED_READY\n"
        ));
        assert!(!serial_has_pid1_boot_seed("ryoku-init: pid=1\n"));
        assert!(serial_has_pid1_boot_seed(
            "ryoku-init: pid=1 seed=mission-008\nRYOKU_BOOT_SEED_READY\n"
        ));
    }
}
