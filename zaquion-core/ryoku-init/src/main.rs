//! `ryoku-init` — minimal PID 1 prototype for the Ryoku Boot Seed / Minimal.
//!
//! # Behavior
//!
//! 1. Announce identity + READY **once** (prefer `/dev/console`, else stdout).
//! 2. Emit [`ryoku_init::BOOT_SEED_READY_MARKER`] **only** when `pid == 1`.
//! 3. If not PID 1: print a diagnostic (no READY), exit non-zero.
//! 4. If PID 1:
//!    - **Original T3** (no `/bin/ryoku-console`): remain idle forever.
//!    - **Ryoku Minimal** (console present): mount proc/sys/devtmpfs (WARN on fail),
//!      ASCII banner, optional graphics profile (Mission 014.1), spawn console once,
//!      reap, idle.
//! 5. PID 1 **never** exits after READY (console/gfx EOF/fail/exit must not kill init).
//!
//! # Not in scope
//!
//! Product rootfs, networking, Desktop, or claiming a finished Ryoku OS product boot.
//! `FIRST_PIXELS=PASS` is never auto-claimed here.

#![forbid(unsafe_code)]

use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::path::Path;
use std::process::{Command, ExitCode, Stdio};
use std::thread;
use std::time::Duration;

use rustix::ffi::CStr;
use rustix::mount::{mount, MountFlags};
use rustix::system::finit_module;

use ryoku_init::{
    allowlisted_module_guest_path, ascii_banner, boot_output, graphics_demo_done_line,
    graphics_demo_start_line, graphics_modules_start_line, guest_any_graphics_profile,
    guest_graphics_profile, guest_interactive_mode, guest_shell_profile, interactive_done_line,
    interactive_start_line, is_pid1, shell_preview_done_line, shell_preview_start_line,
    CONSOLE_BIN_PATH, GRAPHICS_DEMO_BIN_PATH, SHELL_PREVIEW_BIN_PATH, VIRT_DRM_ALLOWLIST,
};

fn write_all_best_effort(mut w: impl Write, bytes: &[u8]) {
    let _ = w.write_all(bytes);
    let _ = w.flush();
}

/// Single-channel announce — avoids READY×3 when stdout/stderr/`/dev/console` share a UART.
fn announce(text: &str) {
    let bytes = text.as_bytes();
    if let Ok(console) = OpenOptions::new().write(true).open("/dev/console") {
        write_all_best_effort(console, bytes);
        return;
    }
    write_all_best_effort(io::stdout(), bytes);
}

/// Mount procfs + sysfs + devtmpfs for hardware/graphics honesty. WARN on failure; never abort.
fn mount_proc_sys_best_effort() {
    for (source, target, fstype) in [
        ("proc", "/proc", "proc"),
        ("sysfs", "/sys", "sysfs"),
        // Populate /dev/fb0 /dev/dri/* when drivers exist; kernel should recreate console.
        ("devtmpfs", "/dev", "devtmpfs"),
    ] {
        // Ensure mountpoint dirs exist (initramfs ships them; recreate if needed).
        let _ = fs::create_dir_all(target);
        match mount(source, target, fstype, MountFlags::empty(), None) {
            Ok(()) => announce(&format!("ryoku-init: mounted {fstype} on {target}\n")),
            Err(err) => announce(&format!(
                "ryoku-init: WARN failed to mount {fstype} on {target}: {err}\n"
            )),
        }
    }
}

/// Open `/dev/console` for child stdio (separate handles — safe Rust, no dup).
fn open_console_rw() -> io::Result<std::fs::File> {
    OpenOptions::new()
        .read(true)
        .write(true)
        .open("/dev/console")
}

fn empty_module_params() -> &'static CStr {
    CStr::from_bytes_with_nul(b"\0").expect("static NUL CStr")
}

/// Load one allowlisted `.ko` via `finit_module`. No arbitrary paths.
fn finit_allowlisted_module(rel: &str) -> Result<(), String> {
    let guest = allowlisted_module_guest_path(rel)?;
    let path = Path::new(&guest);
    if !path.is_file() {
        return Err(format!("missing {guest}"));
    }
    let file = File::open(path).map_err(|e| format!("open {guest}: {e}"))?;
    finit_module(&file, empty_module_params(), 0).map_err(|e| format!("finit_module {guest}: {e}"))
}

/// Graphics profile: load pinned Alpine virt DRM modules (WARN + continue on failure).
fn load_virt_drm_modules_best_effort() {
    announce(&graphics_modules_start_line());
    let mut loaded = 0usize;
    for rel in VIRT_DRM_ALLOWLIST {
        match finit_allowlisted_module(rel) {
            Ok(()) => {
                loaded = loaded.saturating_add(1);
                announce(&format!("ryoku-init: loaded module {rel}\n"));
            }
            Err(err) => {
                announce(&format!("ryoku-init: WARN module load failed: {err}\n"));
                // Continue remaining allowlist — deps may already be present / later stages still try.
            }
        }
    }
    announce(&format!(
        "ryoku-init: graphics modules loaded={loaded}/{}\n",
        VIRT_DRM_ALLOWLIST.len()
    ));
    // Brief settle so devtmpfs can create fb/dri nodes before demo probe.
    thread::sleep(Duration::from_millis(200));
}

/// Honest pre-demo inventory (serial only — never claims FIRST_PIXELS=PASS).
fn announce_graphics_inventory() {
    let pci = Path::new("/sys/bus/pci/devices/0000:00:02.0");
    if pci.exists() {
        let driver = fs::read_link(pci.join("driver"))
            .ok()
            .and_then(|p| p.file_name().map(|s| s.to_string_lossy().into_owned()))
            .unwrap_or_else(|| "unbound".into());
        announce(&format!(
            "ryoku-init: graphics device discovered: PCI 0000:00:02.0 driver={driver}\n"
        ));
    } else {
        announce("ryoku-init: graphics device discovered: no PCI 0000:00:02.0\n");
    }

    let virtio_gpu = Path::new("/sys/module/virtio_gpu").exists()
        || Path::new("/sys/bus/pci/drivers/virtio-gpu-pci").exists();
    if virtio_gpu {
        announce("ryoku-init: graphics driver ready: virtio_gpu module/sysfs present\n");
    } else {
        announce(
            "ryoku-init: graphics driver ready: virtio_gpu NOT present (PCI virtio-pci alone ≠ DRM)\n",
        );
    }

    let fb0 = Path::new("/dev/fb0").exists();
    let card0 = Path::new("/dev/dri/card0").exists();
    let drm_sys = Path::new("/sys/class/drm").exists();
    announce(&format!(
        "ryoku-init: graphics surface available: fb0={} dri_card0={} sysfs_drm={}\n",
        if fb0 { "yes" } else { "no" },
        if card0 { "yes" } else { "no" },
        if drm_sys { "yes" } else { "no" },
    ));
}

/// Controlled start of `/bin/ryoku-shell-preview` once (Mission 015). Prefer over graphics-demo
/// to avoid dual FB presenters in the same guest.
fn run_shell_preview_once_best_effort() {
    announce(&shell_preview_start_line());
    announce_graphics_inventory();

    let stdin = match open_console_rw() {
        Ok(f) => f,
        Err(err) => {
            announce(&shell_preview_done_line(&format!(
                "WARN open console for shell stdin failed: {err}"
            )));
            return;
        }
    };
    let stdout = match open_console_rw() {
        Ok(f) => f,
        Err(err) => {
            announce(&shell_preview_done_line(&format!(
                "WARN open console for shell stdout failed: {err}"
            )));
            return;
        }
    };
    let stderr = match open_console_rw() {
        Ok(f) => f,
        Err(err) => {
            announce(&shell_preview_done_line(&format!(
                "WARN open console for shell stderr failed: {err}"
            )));
            return;
        }
    };

    let child = Command::new(SHELL_PREVIEW_BIN_PATH)
        .env("RYOKU_GRAPHICS_ROOT", "/")
        .env("RYOKU_CONSOLE_ROOT", "/")
        .stdin(Stdio::from(stdin))
        .stdout(Stdio::from(stdout))
        .stderr(Stdio::from(stderr))
        .spawn();

    match child {
        Ok(mut child) => match child.wait() {
            Ok(status) if status.success() => {
                announce(
                    "ryoku-init: shell preview presented (exit 0); graphical guest confirm still NOT_RUN; input NOT_RUN (015.1)\n",
                );
                announce(&shell_preview_done_line(&format!("exit {status}")));
            }
            Ok(status) => {
                announce(&format!(
                    "ryoku-init: WARN shell preview failed (status {status}); serial console continues\n"
                ));
                announce(&shell_preview_done_line(&format!("exit {status}")));
            }
            Err(err) => {
                announce(&format!(
                    "ryoku-init: WARN shell preview wait failed: {err}; serial console continues\n"
                ));
                announce(&shell_preview_done_line(&format!("wait failed: {err}")));
            }
        },
        Err(err) => {
            announce(&format!(
                "ryoku-init: WARN shell preview spawn failed: {err}; serial console continues\n"
            ));
            announce(&shell_preview_done_line(&format!("spawn failed: {err}")));
        }
    }
}

/// Controlled start of `/bin/ryoku-graphics-demo` once. WARN + continue; never blocks forever
/// beyond the child lifetime; never duplicates READY; no arbitrary exec from console path.
fn run_graphics_demo_once_best_effort() {
    announce(&graphics_demo_start_line());
    announce_graphics_inventory();

    let stdin = match open_console_rw() {
        Ok(f) => f,
        Err(err) => {
            announce(&graphics_demo_done_line(&format!(
                "WARN open console for demo stdin failed: {err}"
            )));
            return;
        }
    };
    let stdout = match open_console_rw() {
        Ok(f) => f,
        Err(err) => {
            announce(&graphics_demo_done_line(&format!(
                "WARN open console for demo stdout failed: {err}"
            )));
            return;
        }
    };
    let stderr = match open_console_rw() {
        Ok(f) => f,
        Err(err) => {
            announce(&graphics_demo_done_line(&format!(
                "WARN open console for demo stderr failed: {err}"
            )));
            return;
        }
    };

    let child = Command::new(GRAPHICS_DEMO_BIN_PATH)
        .env("RYOKU_GRAPHICS_ROOT", "/")
        .env("RYOKU_CONSOLE_ROOT", "/")
        .stdin(Stdio::from(stdin))
        .stdout(Stdio::from(stdout))
        .stderr(Stdio::from(stderr))
        .spawn();

    match child {
        Ok(mut child) => match child.wait() {
            Ok(status) if status.success() => {
                announce("ryoku-init: graphics presented successfully: demo exit 0 (FIRST_PIXELS=PASS_MANUAL only after human visual confirm; never auto-PASS)\n");
                announce(&graphics_demo_done_line(&format!("exit {status}")));
            }
            Ok(status) => {
                announce(&format!(
                    "ryoku-init: WARN graphics demo failed (status {status}); serial console continues\n"
                ));
                announce(&graphics_demo_done_line(&format!("exit {status}")));
            }
            Err(err) => {
                announce(&format!(
                    "ryoku-init: WARN graphics demo wait failed: {err}; serial console continues\n"
                ));
                announce(&graphics_demo_done_line(&format!("wait failed: {err}")));
            }
        },
        Err(err) => {
            announce(&format!(
                "ryoku-init: WARN graphics demo spawn failed: {err}; serial console continues\n"
            ));
            announce(&graphics_demo_done_line(&format!("spawn failed: {err}")));
        }
    }
}

/// Spawn `ryoku-console` once, wait/reap, never restart, never exit PID 1.
fn run_interactive_console_once() {
    announce(&interactive_start_line());

    let stdin = match open_console_rw() {
        Ok(f) => f,
        Err(err) => {
            announce(&interactive_done_line(&format!(
                "open /dev/console stdin failed: {err}"
            )));
            return;
        }
    };
    let stdout = match open_console_rw() {
        Ok(f) => f,
        Err(err) => {
            announce(&interactive_done_line(&format!(
                "open /dev/console stdout failed: {err}"
            )));
            return;
        }
    };
    let stderr = match open_console_rw() {
        Ok(f) => f,
        Err(err) => {
            announce(&interactive_done_line(&format!(
                "open /dev/console stderr failed: {err}"
            )));
            return;
        }
    };

    // Guest Minimal: explicit root `/` so host REPLs without RYOKU_CONSOLE_ROOT
    // never fall back to touching the real host filesystem.
    let child = Command::new(CONSOLE_BIN_PATH)
        .env("RYOKU_CONSOLE_ROOT", "/")
        .env("RYOKU_HWPROBE_ROOT", "/")
        .stdin(Stdio::from(stdin))
        .stdout(Stdio::from(stdout))
        .stderr(Stdio::from(stderr))
        .spawn();

    match child {
        Ok(mut child) => match child.wait() {
            Ok(status) => {
                announce(&interactive_done_line(&format!("exit {status}")));
            }
            Err(err) => {
                announce(&interactive_done_line(&format!("wait failed: {err}")));
            }
        },
        Err(err) => {
            announce(&interactive_done_line(&format!("spawn failed: {err}")));
        }
    }
}

fn idle_forever() -> ! {
    loop {
        thread::sleep(Duration::from_secs(3600));
    }
}

fn main() -> ExitCode {
    let pid = std::process::id();
    let text = boot_output(pid);
    announce(&text);

    if !is_pid1(pid) {
        // Never claim READY from a non-init process (host/unit-test invocations).
        return ExitCode::from(1);
    }

    // READY already emitted. Optional Minimal interactive path (separate from T3).
    if guest_interactive_mode() {
        // Mounts are Minimal-only; T3 (no console binary) skips this and stays idle.
        mount_proc_sys_best_effort();
        announce(ascii_banner());
        // Graphics/shell profile: load allowlisted modules once, then start exactly one
        // FB presenter (shell preferred) to avoid dual presenters fighting over fb0.
        // Serial Minimal omits both binaries → skipped (T3/First-Pixels packages unchanged).
        if guest_any_graphics_profile() {
            load_virt_drm_modules_best_effort();
            if guest_shell_profile() {
                run_shell_preview_once_best_effort();
            } else if guest_graphics_profile() {
                run_graphics_demo_once_best_effort();
            }
        }
        run_interactive_console_once();
        // No uncontrolled restart — fall through to idle.
    }

    // PID 1 must not return (T3 and post-console Minimal alike).
    idle_forever();
}
