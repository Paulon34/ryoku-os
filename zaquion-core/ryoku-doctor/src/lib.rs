//! Ryoku Doctor — read-only host diagnostics for Ryoku OS development.
//!
//! # Design
//!
//! The CLI is a thin wrapper around [`Doctor`]. All probing goes through two
//! traits so unit tests can simulate broken tools, missing KVM nodes, or
//! surprising command output without touching the real host:
//!
//! - [`CommandRunner`] — run external programs (`rustc`, `git`, `qemu-…`)
//! - [`FsProbe`] — read small files and check path access (`/dev/kvm`, os-release)
//!
//! Missing QEMU or inaccessible KVM is reported as **WARN** on **optional**
//! checks. That must never make `cargo test` / `cargo build` fail: those are
//! separate from the doctor's process exit code for optional tooling.

#![forbid(unsafe_code)]

pub mod check;
pub mod doctor;
pub mod finding;
pub mod probe;
pub mod report;
pub mod runner;

pub use check::run_all_checks;
pub use doctor::Doctor;
pub use finding::{Finding, Importance, Severity};
pub use probe::{FsProbe, HostFsProbe, MockFs};
pub use report::{format_report, worst_required_severity};
pub use runner::{CommandOutput, CommandRunner, HostCommandRunner, MockRunner};
