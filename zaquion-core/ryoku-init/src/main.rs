//! `ryoku-init` — minimal PID 1 prototype for the Ryoku Boot Seed.
//!
//! # Behavior
//!
//! 1. Announce identity on stdout (guest serial when run as `/init`).
//! 2. Print [`ryoku_init::BOOT_SEED_READY_MARKER`].
//! 3. Remain as PID 1 (idle loop) so the kernel does not panic on init exit.
//!
//! # Not in scope
//!
//! Mounting a real rootfs, networking, package managers, Desktop, or claiming a
//! finished Ryoku OS product boot.

#![forbid(unsafe_code)]

use std::io::{self, Write};
use std::thread;
use std::time::Duration;

use ryoku_init::boot_banner;

fn main() {
    let pid = std::process::id();
    let banner = boot_banner(pid);
    // Best-effort console write; ignore EPIPE if no console yet.
    let _ = io::stdout().write_all(banner.as_bytes());
    let _ = io::stdout().flush();
    let _ = io::stderr().write_all(banner.as_bytes());
    let _ = io::stderr().flush();

    // PID 1 must not exit. Future missions may pivot_root / exec a real userland.
    loop {
        thread::sleep(Duration::from_secs(3600));
    }
}
