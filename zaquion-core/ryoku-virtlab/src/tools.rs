//! Host tool detection for the Virtual Lab (read-only).

use std::path::Path;
use std::process::Command;

use crate::config::AccelMode;

const KVM_PATH: &str = "/dev/kvm";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AccelChoice {
    Kvm,
    Tcg,
}

impl AccelChoice {
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Kvm => "kvm",
            Self::Tcg => "tcg",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ToolsReport {
    pub qemu_system: Option<String>,
    pub qemu_img: Option<String>,
    pub kvm_device_present: bool,
    pub kvm_usable: bool,
    /// Software emulation is available whenever the system emulator binary exists.
    pub tcg_possible: bool,
}

impl ToolsReport {
    #[must_use]
    pub fn qemu_present(&self) -> bool {
        self.qemu_system.is_some()
    }

    /// Select accel for a config, or explain why T1 cannot run.
    pub fn select_accel(&self, mode: AccelMode) -> Result<AccelChoice, String> {
        if !self.qemu_present() {
            return Err("qemu-system-x86_64 not found on PATH".into());
        }
        match mode {
            AccelMode::Tcg => Ok(AccelChoice::Tcg),
            AccelMode::Kvm => {
                if self.kvm_usable {
                    Ok(AccelChoice::Kvm)
                } else {
                    Err("KVM requested but /dev/kvm is missing or not usable".into())
                }
            }
            AccelMode::Auto => {
                if self.kvm_usable {
                    Ok(AccelChoice::Kvm)
                } else {
                    Ok(AccelChoice::Tcg)
                }
            }
        }
    }
}

/// Probe for external binaries / device nodes.
pub trait ToolProbe {
    fn version_line(&self, program: &str, args: &[&str]) -> Option<String>;
    fn path_exists(&self, path: &Path) -> bool;
    fn path_readable(&self, path: &Path) -> bool;
    fn path_writable(&self, path: &Path) -> bool;
}

#[derive(Debug, Default, Clone, Copy)]
pub struct HostToolProbe;

impl ToolProbe for HostToolProbe {
    fn version_line(&self, program: &str, args: &[&str]) -> Option<String> {
        let output = Command::new(program).args(args).output().ok()?;
        if !output.status.success() {
            return None;
        }
        let stdout = String::from_utf8_lossy(&output.stdout);
        stdout
            .lines()
            .map(str::trim)
            .find(|l| !l.is_empty())
            .map(str::to_string)
    }

    fn path_exists(&self, path: &Path) -> bool {
        path.exists()
    }

    fn path_readable(&self, path: &Path) -> bool {
        std::fs::OpenOptions::new().read(true).open(path).is_ok()
    }

    fn path_writable(&self, path: &Path) -> bool {
        std::fs::OpenOptions::new().write(true).open(path).is_ok()
    }
}

#[must_use]
pub fn detect_tools<P: ToolProbe>(probe: &P) -> ToolsReport {
    let qemu_system = probe.version_line("qemu-system-x86_64", &["--version"]);
    let qemu_img = probe.version_line("qemu-img", &["--version"]);
    let kvm_path = Path::new(KVM_PATH);
    let kvm_device_present = probe.path_exists(kvm_path);
    let kvm_usable =
        kvm_device_present && probe.path_readable(kvm_path) && probe.path_writable(kvm_path);
    let tcg_possible = qemu_system.is_some();

    ToolsReport {
        qemu_system,
        qemu_img,
        kvm_device_present,
        kvm_usable,
        tcg_possible,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use std::path::PathBuf;

    #[derive(Default)]
    struct MockProbe {
        versions: HashMap<String, String>,
        nodes: HashMap<PathBuf, (bool, bool, bool)>,
    }

    impl MockProbe {
        fn with_qemu(mut self, line: &str) -> Self {
            self.versions
                .insert("qemu-system-x86_64".into(), line.into());
            self
        }

        fn with_kvm(mut self, present: bool, rw: bool) -> Self {
            self.nodes
                .insert(PathBuf::from(KVM_PATH), (present, rw, rw));
            self
        }
    }

    impl ToolProbe for MockProbe {
        fn version_line(&self, program: &str, _args: &[&str]) -> Option<String> {
            self.versions.get(program).cloned()
        }

        fn path_exists(&self, path: &Path) -> bool {
            self.nodes.get(path).map(|(e, _, _)| *e).unwrap_or(false)
        }

        fn path_readable(&self, path: &Path) -> bool {
            self.nodes.get(path).map(|(_, r, _)| *r).unwrap_or(false)
        }

        fn path_writable(&self, path: &Path) -> bool {
            self.nodes.get(path).map(|(_, _, w)| *w).unwrap_or(false)
        }
    }

    #[test]
    fn auto_falls_back_to_tcg_without_kvm() {
        let report = detect_tools(
            &MockProbe::default()
                .with_qemu("QEMU 8")
                .with_kvm(true, false),
        );
        assert!(report.tcg_possible);
        assert!(!report.kvm_usable);
        assert_eq!(
            report.select_accel(AccelMode::Auto).unwrap(),
            AccelChoice::Tcg
        );
    }

    #[test]
    fn without_qemu_tcg_not_possible() {
        let report = detect_tools(&MockProbe::default());
        assert!(!report.tcg_possible);
        assert!(report.select_accel(AccelMode::Auto).is_err());
    }
}
