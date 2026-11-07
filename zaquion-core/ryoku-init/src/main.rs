//! `ryoku-init` — minimal PID 1 prototype for the Ryoku Boot Seed / Minimal.
//!
//! # Behavior
//!
//! 1. Announce identity on stdout/stderr and `/dev/console` when present.
//! 2. Emit [`ryoku_init::BOOT_SEED_READY_MARKER`] **only** when `pid == 1`.
//! 3. If not PID 1: print a diagnostic (no READY), exit non-zero.
//! 4. If PID 1:
//!    - **Original T3** (no `/bin/ryoku-console`): remain idle forever.
//!    - **Ryoku Minimal** (console present): spawn console once with stdio on
//!      `/dev/console`, reap it, then remain idle forever (no uncontrolled restart).
//! 5. PID 1 **never** exits after READY (console EOF/fail/exit must not kill init).
//!
//! # Not in scope
//!
//! Mounting a real rootfs, networking, package managers, Desktop, or claiming a
//! finished Ryoku OS product boot.

#![forbid(unsafe_code)]

use std::fs::OpenOptions;
use std::io::{self, Write};
use std::process::{Command, ExitCode, Stdio};
use std::thread;
use std::time::Duration;

use ryoku_init::{
    boot_output, guest_interactive_mode, interactive_done_line, interactive_start_line, is_pid1,
    CONSOLE_BIN_PATH,
};

fn write_all_best_effort(mut w: impl Write, bytes: &[u8]) {
    let _ = w.write_all(bytes);
    let _ = w.flush();
}

fn announce(text: &str) {
    let bytes = text.as_bytes();
    write_all_best_effort(io::stdout(), bytes);
    write_all_best_effort(io::stderr(), bytes);
    if let Ok(console) = OpenOptions::new().write(true).open("/dev/console") {
        write_all_best_effort(console, bytes);
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
        run_interactive_console_once();
        // No uncontrolled restart — fall through to idle.
    }

    // PID 1 must not return (T3 and post-console Minimal alike).
    idle_forever();
}
