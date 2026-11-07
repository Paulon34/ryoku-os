//! `ryoku-init` — minimal PID 1 prototype for the Ryoku Boot Seed.
//!
//! # Behavior
//!
//! 1. Announce identity on stdout/stderr and `/dev/console` when present.
//! 2. Print [`ryoku_init::BOOT_SEED_READY_MARKER`].
//! 3. Remain as PID 1 (idle loop) so the kernel does not panic on init exit.
//!
//! # PID 1 notes
//!
//! - This seed does **not** spawn children; no SIGCHLD reaper is installed yet.
//! - On Linux, fatal signals without a handler are ignored for PID 1; we still
//!   avoid intentional `process::exit` after the banner.
//! - Panic path uses workspace `panic = "abort"` (release) so we do not unwind
//!   out of `main` and leave the guest without an init.
//!
//! # Not in scope
//!
//! Mounting a real rootfs, networking, package managers, Desktop, or claiming a
//! finished Ryoku OS product boot.

#![forbid(unsafe_code)]

use std::fs::OpenOptions;
use std::io::{self, Write};
use std::thread;
use std::time::Duration;

use ryoku_init::boot_banner;

fn write_all_best_effort(mut w: impl Write, bytes: &[u8]) {
    let _ = w.write_all(bytes);
    let _ = w.flush();
}

fn announce(banner: &str) {
    let bytes = banner.as_bytes();
    // Kernel typically wires init stdio to the console when `console=` is set.
    write_all_best_effort(io::stdout(), bytes);
    write_all_best_effort(io::stderr(), bytes);
    // Explicit console device when present (devtmpfs / pre-created node).
    if let Ok(console) = OpenOptions::new().write(true).open("/dev/console") {
        write_all_best_effort(console, bytes);
    }
}

fn main() {
    let pid = std::process::id();
    let banner = boot_banner(pid);
    announce(&banner);

    // PID 1 must not return. Future missions may pivot_root / exec a real userland.
    loop {
        thread::sleep(Duration::from_secs(3600));
    }
}
