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
//!
//! Mission 014.1 adds a **graphics profile** when `/bin/ryoku-graphics-demo` is
//! present: PID 1 may load an allowlisted Alpine virt DRM module set and start
//! the demo once. Serial Minimal / T3 packages omit that binary → unchanged.

#![forbid(unsafe_code)]

use std::path::{Component, Path};

/// Printed by `ryoku-init` as process identity.
pub const PROCESS_IDENTITY: &str = "ryoku-init";

/// Stable serial marker for Virtual Lab T3 — emitted **only** when running as PID 1.
pub const BOOT_SEED_READY_MARKER: &str = "RYOKU_BOOT_SEED_READY";

/// Identity line substring required on guest serial for T3 PASS (`ryoku-init: pid=1`).
pub const PID1_IDENTITY_MARKER: &str = "ryoku-init: pid=1";

/// Guest path for the interactive console binary (Ryoku Minimal initramfs only).
pub const CONSOLE_BIN_PATH: &str = "/bin/ryoku-console";

/// Guest path for the graphics demo (graphics package only — Mission 014/014.1).
pub const GRAPHICS_DEMO_BIN_PATH: &str = "/bin/ryoku-graphics-demo";

/// Guest path for the shell preview (shell package only — Mission 015).
pub const SHELL_PREVIEW_BIN_PATH: &str = "/bin/ryoku-shell-preview";

/// Guest modules root for the pinned Alpine virt lab kernel (Mission 014.1).
pub const VIRT_DRM_MODULES_ROOT: &str = "/lib/modules/6.12.114-0-virt";

/// Allowlisted DRM/fb modules relative to [`VIRT_DRM_MODULES_ROOT`] (load order).
///
/// Exact Alpine netboot-3.21.9 modloop members — never NixOS host `/lib/modules`.
pub const VIRT_DRM_ALLOWLIST: &[&str] = &[
    "kernel/drivers/virtio/virtio_dma_buf.ko",
    "kernel/drivers/video/fbdev/core/syscopyarea.ko",
    "kernel/drivers/video/fbdev/core/sysfillrect.ko",
    "kernel/drivers/video/fbdev/core/sysimgblt.ko",
    "kernel/drivers/video/fbdev/core/fb_sys_fops.ko",
    "kernel/drivers/gpu/drm/drm_panel_orientation_quirks.ko",
    "kernel/drivers/i2c/i2c-core.ko",
    "kernel/drivers/gpu/drm/drm.ko",
    "kernel/drivers/video/fbdev/core/fb.ko",
    "kernel/drivers/gpu/drm/drm_kms_helper.ko",
    "kernel/drivers/gpu/drm/drm_shmem_helper.ko",
    "kernel/drivers/gpu/drm/virtio/virtio-gpu.ko",
    // Mission 015.1 — guest evdev + virtio input (after DRM/fb).
    "kernel/drivers/input/evdev.ko",
    "kernel/drivers/virtio/virtio_input.ko",
];

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

/// True when the graphics demo binary is present (graphics package profile).
#[must_use]
pub fn graphics_demo_present(demo_path: &Path) -> bool {
    demo_path.is_file()
}

/// Default guest check for graphics profile (Mission 014.1).
#[must_use]
pub fn guest_graphics_profile() -> bool {
    graphics_demo_present(Path::new(GRAPHICS_DEMO_BIN_PATH))
}

/// True when the shell preview binary is present (Mission 015 package).
#[must_use]
pub fn shell_preview_present(path: &Path) -> bool {
    path.is_file()
}

/// Default guest check for shell profile (Mission 015).
///
/// Prefer shell over graphics-demo when both exist (packages should not ship both).
#[must_use]
pub fn guest_shell_profile() -> bool {
    shell_preview_present(Path::new(SHELL_PREVIEW_BIN_PATH))
}

/// True when any DRM-backed graphical guest binary should be started.
#[must_use]
pub fn guest_any_graphics_profile() -> bool {
    guest_shell_profile() || guest_graphics_profile()
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

/// Serial line before allowlisted DRM module load (graphics profile only).
#[must_use]
pub fn graphics_modules_start_line() -> String {
    format!(
        "{PROCESS_IDENTITY}: graphics profile — loading allowlisted virt DRM modules \
         under {VIRT_DRM_MODULES_ROOT}\n"
    )
}

/// Serial line before controlled graphics demo start (never duplicates READY).
#[must_use]
pub fn graphics_demo_start_line() -> String {
    format!("{PROCESS_IDENTITY}: graphics profile — starting {GRAPHICS_DEMO_BIN_PATH}\n")
}

/// Serial line when graphics demo exits or fails; PID 1 continues to console.
#[must_use]
pub fn graphics_demo_done_line(detail: &str) -> String {
    format!("{PROCESS_IDENTITY}: graphics demo finished ({detail}); continuing\n")
}

/// Serial line before controlled shell preview start (Mission 015).
#[must_use]
pub fn shell_preview_start_line() -> String {
    format!("{PROCESS_IDENTITY}: shell profile — starting {SHELL_PREVIEW_BIN_PATH}\n")
}

/// Serial line when shell preview exits or fails; PID 1 continues to console.
#[must_use]
pub fn shell_preview_done_line(detail: &str) -> String {
    format!("{PROCESS_IDENTITY}: shell preview finished ({detail}); continuing\n")
}

/// Refuse `..`, absolute paths, and names outside the allowlist.
#[must_use]
pub fn is_allowlisted_module_rel(rel: &str) -> bool {
    if rel.is_empty() || rel.starts_with('/') || rel.contains('\0') {
        return false;
    }
    for c in Path::new(rel).components() {
        match c {
            Component::Normal(_) => {}
            Component::CurDir
            | Component::ParentDir
            | Component::RootDir
            | Component::Prefix(_) => {
                return false;
            }
        }
    }
    VIRT_DRM_ALLOWLIST.iter().any(|a| *a == rel)
}

/// Resolve guest path for an allowlisted module relative path.
pub fn allowlisted_module_guest_path(rel: &str) -> Result<String, String> {
    if !is_allowlisted_module_rel(rel) {
        return Err(format!("module path not allowlisted: {rel}"));
    }
    Ok(format!("{VIRT_DRM_MODULES_ROOT}/{rel}"))
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

/// Mission 016.2 — allowlisted kernel cmdline keys → guest env for shell-preview.
///
/// Only these keys/values are forwarded. T3 / Minimal append paths that omit
/// `ryoku.*` are unchanged.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct RyokuCmdlineEnv {
    pub profile: Option<&'static str>,
    pub perf_overlay: Option<&'static str>,
    pub controlled_benchmark: Option<&'static str>,
}

/// Parse allowlisted `ryoku.*` tokens from a kernel cmdline string.
#[must_use]
pub fn parse_ryoku_cmdline(cmdline: &str) -> RyokuCmdlineEnv {
    let mut out = RyokuCmdlineEnv::default();
    for tok in cmdline.split_whitespace() {
        if let Some(v) = tok.strip_prefix("ryoku.profile=") {
            out.profile = match v {
                "lite" | "l" => Some("lite"),
                "balanced" | "bal" | "b" => Some("balanced"),
                "ultra" | "u" => Some("ultra"),
                _ => out.profile,
            };
        } else if let Some(v) = tok.strip_prefix("ryoku.perf_overlay=") {
            out.perf_overlay = match v {
                "0" | "false" | "FALSE" => Some("0"),
                "1" | "true" | "TRUE" => Some("1"),
                _ => out.perf_overlay,
            };
        } else if let Some(v) = tok.strip_prefix("ryoku.controlled_benchmark=") {
            out.controlled_benchmark = match v {
                "0" | "false" | "FALSE" => Some("0"),
                "1" | "true" | "TRUE" => Some("1"),
                _ => out.controlled_benchmark,
            };
        }
        // Any other token (including unknown ryoku.*) is ignored — no open env injection.
    }
    out
}

/// Read `/proc/cmdline` and parse allowlisted Ryoku params (empty on failure).
#[must_use]
pub fn ryoku_cmdline_from_proc() -> RyokuCmdlineEnv {
    match std::fs::read_to_string("/proc/cmdline") {
        Ok(s) => parse_ryoku_cmdline(&s),
        Err(_) => RyokuCmdlineEnv::default(),
    }
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

    #[test]
    fn graphics_profile_absent_by_default_path() {
        let missing = Path::new("/bin/ryoku-graphics-demo-definitely-missing-for-test");
        assert!(!graphics_demo_present(missing));
    }

    #[test]
    fn graphics_messages_do_not_emit_ready_or_first_pixels_pass() {
        for s in [
            graphics_modules_start_line(),
            graphics_demo_start_line(),
            graphics_demo_done_line("ok"),
            shell_preview_start_line(),
            shell_preview_done_line("ok"),
        ] {
            assert!(!s.contains(BOOT_SEED_READY_MARKER), "{s}");
            assert!(!s.contains("FIRST_PIXELS=PASS"), "{s}");
        }
        assert!(graphics_demo_start_line().contains(GRAPHICS_DEMO_BIN_PATH));
        assert!(shell_preview_start_line().contains(SHELL_PREVIEW_BIN_PATH));
    }

    #[test]
    fn shell_profile_absent_by_default_path() {
        let missing = Path::new("/bin/ryoku-shell-preview-definitely-missing-for-test");
        assert!(!shell_preview_present(missing));
    }

    #[test]
    fn allowlist_rejects_escape_and_unknown() {
        assert!(is_allowlisted_module_rel(
            "kernel/drivers/gpu/drm/virtio/virtio-gpu.ko"
        ));
        assert!(!is_allowlisted_module_rel("../etc/passwd"));
        assert!(!is_allowlisted_module_rel("/lib/modules/x.ko"));
        assert!(!is_allowlisted_module_rel("kernel/drivers/gpu/drm/evil.ko"));
        assert!(allowlisted_module_guest_path("kernel/drivers/gpu/drm/drm.ko").is_ok());
        assert!(allowlisted_module_guest_path("../x").is_err());
    }

    #[test]
    fn allowlist_has_drm_then_input_modules() {
        assert_eq!(VIRT_DRM_ALLOWLIST.len(), 14);
        assert!(VIRT_DRM_ALLOWLIST[11].ends_with("virtio-gpu.ko"));
        assert!(VIRT_DRM_ALLOWLIST[12].ends_with("evdev.ko"));
        assert!(VIRT_DRM_ALLOWLIST[13].ends_with("virtio_input.ko"));
    }

    #[test]
    fn ryoku_cmdline_allowlist_parses_known_only() {
        let e = parse_ryoku_cmdline(
            "console=ttyS0 ryoku.profile=ultra ryoku.perf_overlay=1 \
             ryoku.controlled_benchmark=1 ryoku.evil=1 PATH=/evil",
        );
        assert_eq!(e.profile, Some("ultra"));
        assert_eq!(e.perf_overlay, Some("1"));
        assert_eq!(e.controlled_benchmark, Some("1"));
        // Unknown keys ignored (no open injection).
        let empty = parse_ryoku_cmdline("console=ttyS0 ryoku.unknown=1");
        assert_eq!(empty, RyokuCmdlineEnv::default());
        let bad = parse_ryoku_cmdline("ryoku.profile=gaming ryoku.perf_overlay=maybe");
        assert_eq!(bad.profile, None);
        assert_eq!(bad.perf_overlay, None);
    }

    #[test]
    fn t3_style_cmdline_unchanged_empty_ryoku_env() {
        assert_eq!(
            parse_ryoku_cmdline("console=ttyS0 earlyprintk=serial"),
            RyokuCmdlineEnv::default()
        );
    }
}
