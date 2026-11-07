//! `ryoku-init` — minimal PID 1 prototype for the Ryoku Boot Seed.
//!
//! # Behavior
//!
//! 1. Announce identity on stdout/stderr and `/dev/console` when present.
//! 2. Emit [`ryoku_init::BOOT_SEED_READY_MARKER`] **only** when `pid == 1`.
//! 3. If not PID 1: print a diagnostic (no READY), exit non-zero.
//! 4. If PID 1: remain running (idle loop) so the kernel does not panic on init exit.
//!
//! # Not in scope
//!
//! Mounting a real rootfs, networking, package managers, Desktop, or claiming a
//! finished Ryoku OS product boot.

#![forbid(unsafe_code)]

use std::fs::OpenOptions;
use std::io::{self, Write};
use std::process::ExitCode;
use std::thread;
use std::time::Duration;

use ryoku_init::{boot_output, is_pid1};

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

fn main() -> ExitCode {
    let pid = std::process::id();
    let text = boot_output(pid);
    announce(&text);

    if !is_pid1(pid) {
        // Never claim READY from a non-init process (host/unit-test invocations).
        return ExitCode::from(1);
    }

    // PID 1 must not return.
    loop {
        thread::sleep(Duration::from_secs(3600));
    }
}
