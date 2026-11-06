//! Ryoku Virtual Lab — safe QEMU harness (T0 / T1).
//!
//! # Safety contract
//!
//! - Never uses a shell to build QEMU command lines (`Vec<String>` argv only).
//! - Never attaches host physical disks (`/dev/sd*`, `/dev/nvme*`, …).
//! - Never uses sudo, never installs packages, never changes KVM permissions.
//! - T1 may start the **emulator**; OS boot success requires an authorized guest image
//!   (not claimed without a bootable kernel/system under test).

#![forbid(unsafe_code)]

pub mod argv;
pub mod config;
pub mod exec;
pub mod report;
pub mod security;
pub mod status;
pub mod t0;
pub mod t1;
pub mod tools;

pub use config::{AccelMode, NetworkMode, VmConfig};
pub use report::format_lab_report;
pub use status::{CaseResult, Outcome};
pub use t0::run_t0;
pub use t1::run_t1;
pub use tools::{detect_tools, HostToolProbe, ToolProbe, ToolsReport};
