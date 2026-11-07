//! `ryoku-init` — minimal PID 1 prototype for the Ryoku Boot Seed / Minimal.
//!
//! # Behavior
//!
//! 1. Announce identity + READY **once** (prefer `/dev/console`, else stdout).
//! 2. Emit [`ryoku_init::BOOT_SEED_READY_MARKER`] **only** when `pid == 1`.
//! 3. If not PID 1: print a diagnostic (no READY), exit non-zero.
//! 4. If PID 1:
//!    - **Original T3** (no `/bin/ryoku-console`): remain idle forever.
//!    - **Ryoku Minimal** (console present): mount proc/sys (WARN on fail),
//!      ASCII banner, spawn console once on `/dev/console`, reap, idle.
//! 5. PID 1 **never** exits after READY (console EOF/fail/exit must not kill init).
//!
//! # Not in scope
//!
//! Product rootfs, networking, Desktop, or claiming a finished Ryoku OS product boot.

#![forbid(unsafe_code)]

use std::fs::OpenOptions;
use std::io::{self, Write};
use std::process::{Command, ExitCode, Stdio};
use std::thread;
use std::time::Duration;

use rustix::mount::{mount, MountFlags};

use ryoku_init::{
    ascii_banner, boot_output, guest_interactive_mode, interactive_done_line,
    interactive_start_line, is_pid1, CONSOLE_BIN_PATH,
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

/// Mount procfs + sysfs for hardware probe honesty. WARN on failure; never abort console.
fn mount_proc_sys_best_effort() {
    for (source, target, fstype) in [("proc", "/proc", "proc"), ("sysfs", "/sys", "sysfs")] {
        // Ensure mountpoint dirs exist (initramfs ships them; recreate if needed).
        let _ = std::fs::create_dir_all(target);
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
        run_interactive_console_once();
        // No uncontrolled restart — fall through to idle.
    }

    // PID 1 must not return (T3 and post-console Minimal alike).
    idle_forever();
}
