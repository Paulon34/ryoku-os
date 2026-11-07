//! Ryoku Virtual Lab — safe QEMU harness (T0 / T1 / first-boot / boot-seed).
//!
//! # Safety contract
//!
//! - Never uses a shell to build QEMU command lines (`Vec<String>` argv only).
//! - Never attaches host physical disks (`/dev/sd*`, `/dev/nvme*`, …).
//! - Never uses sudo, never installs packages, never changes KVM permissions.
//! - T1 may start the **emulator**; guest OS boot requires an authorized image.
//! - **Reference Linux boot ≠ Ryoku OS boot** (see `boot` / docs/testing/reference-linux.md).
//! - **Boot seed ≠ Ryoku OS product boot** (see `boot_seed` / docs/testing/boot-seed.md).

#![forbid(unsafe_code)]

pub mod argv;
pub mod boot;
pub mod boot_seed;
pub mod config;
pub mod exec;
pub mod initramfs;
pub mod lab;
pub mod report;
pub mod security;
pub mod status;
pub mod t0;
pub mod t1;
pub mod tools;

pub use boot::run_first_boot;
pub use boot_seed::run_boot_seed;
pub use config::{AccelMode, NetworkMode, VmConfig};
pub use lab::{discover_lab_root_from, resolve_lab_asset};
pub use report::format_lab_report;
pub use status::{CaseResult, Outcome};
pub use t0::run_t0;
pub use t1::run_t1;
pub use tools::{detect_tools, HostToolProbe, ToolProbe, ToolsReport};
