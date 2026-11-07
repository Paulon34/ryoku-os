//! Ryoku Boot Seed — shared identity constants and helpers (Mission 008 / 012).
//!
//! This is a **prototype init**, not a finished Ryoku userland or product OS boot.
//! A future T3 QEMU run may PASS `t3.boot_seed` when the guest serial contains
//! both [`PID1_IDENTITY_MARKER`] and [`BOOT_SEED_READY_MARKER`] from a real PID 1
//! process. That is still **not** a full Ryoku OS product boot.
//!
//! Mission 012 adds an **optional** interactive path: when `/bin/ryoku-console`
//! is present in the guest (Ryoku Minimal initramfs), PID 1 may spawn it once
//! after READY. Mission 013 mounts `proc`/`sys` (WARN on fail) and prints an
//! ASCII banner before that spawn. The original Boot Seed initramfs lacks the
//! console binary, so T3 behavior stays idle-after-READY with **no** mounts /
//! **no** console (READY contract unchanged).

#![forbid(unsafe_code)]

use std::path::Path;

/// Printed by `ryoku-init` as process identity.
pub const PROCESS_IDENTITY: &str = "ryoku-init";

/// Stable serial marker for Virtual Lab T3 — emitted **only** when running as PID 1.
pub const BOOT_SEED_READY_MARKER: &str = "RYOKU_BOOT_SEED_READY";

/// Identity line substring required on guest serial for T3 PASS (`ryoku-init: pid=1`).
pub const PID1_IDENTITY_MARKER: &str = "ryoku-init: pid=1";

/// Guest path for the interactive console binary (Ryoku Minimal initramfs only).
pub const CONSOLE_BIN_PATH: &str = "/bin/ryoku-console";

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

/// Explicit interactive mode: guest has a regular file at [`CONSOLE_BIN_PATH`].
///
/// Original T3 Boot Seed initramfs does **not** ship this path → returns false →
/// PID 1 stays in the idle loop (exact prior behavior).
#[must_use]
pub fn interactive_console_present(console_path: &Path) -> bool {
    console_path.is_file()
}

/// Default guest check for interactive mode.
#[must_use]
pub fn guest_interactive_mode() -> bool {
    interactive_console_present(Path::new(CONSOLE_BIN_PATH))
}

/// Message when interactive console will be started (after READY; never fakes READY).
#[must_use]
pub fn interactive_start_line() -> String {
    format!("{PROCESS_IDENTITY}: interactive mode — spawning {CONSOLE_BIN_PATH}\n")
}

/// Message when console child exits or fails; PID 1 remains.
#[must_use]
pub fn interactive_done_line(detail: &str) -> String {
    format!("{PROCESS_IDENTITY}: console finished ({detail}); remaining as PID 1\n")
}

/// ASCII banner after READY / mounts, before console (Mission 013).
/// Splash/artwork for Mission 014 is documentation-only — this stays plain ASCII.
#[must_use]
pub fn ascii_banner() -> &'static str {
    "\
========================================\n\
  Ryoku Minimal\n\
  interactive lab console\n\
  (not a product OS boot)\n\
========================================\n"
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

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

    #[test]
    fn interactive_absent_by_default_path() {
        // Host unit tests are not a guest Minimal FS — console binary usually absent.
        // Behavior under test: missing path ⇒ not interactive (T3-compatible).
        let missing = Path::new("/bin/ryoku-console-definitely-missing-for-test");
        assert!(!interactive_console_present(missing));
    }

    #[test]
    fn interactive_present_when_file_exists() {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("ryoku-init-interactive-{nanos}"));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let bin = dir.join("ryoku-console");
        fs::write(&bin, b"fake").unwrap();
        assert!(interactive_console_present(&bin));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn interactive_messages_do_not_emit_ready() {
        assert!(!interactive_start_line().contains(BOOT_SEED_READY_MARKER));
        assert!(!interactive_done_line("ok").contains(BOOT_SEED_READY_MARKER));
        assert!(interactive_start_line().contains(CONSOLE_BIN_PATH));
    }

    #[test]
    fn ascii_banner_is_plain_and_honest() {
        let b = ascii_banner();
        assert!(b.contains("Ryoku Minimal"));
        assert!(b.contains("not a product OS boot"));
        assert!(!b.contains(BOOT_SEED_READY_MARKER));
        assert!(b.is_ascii());
    }
}
