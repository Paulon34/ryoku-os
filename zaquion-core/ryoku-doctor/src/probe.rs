//! Filesystem probes behind a trait (testable, read-only).

use std::collections::HashMap;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

/// Read-only view of the host filesystem pieces the doctor cares about.
pub trait FsProbe {
    /// Read a small UTF-8 (lossy) text file.
    fn read_to_string(&self, path: &Path) -> Result<String, String>;

    /// Whether the path exists (follows the same rules as `Path::exists`).
    fn exists(&self, path: &Path) -> bool;

    /// Whether the current process can open the path for read.
    fn readable(&self, path: &Path) -> bool;

    /// Whether the current process can open the path for write.
    ///
    /// For `/dev/kvm`, write access is what QEMU typically needs; we only
    /// *check* — we never chmod or change group membership.
    fn writable(&self, path: &Path) -> bool;
}

/// Real host probes using `std::fs` only.
#[derive(Debug, Default, Clone, Copy)]
pub struct HostFsProbe;

impl FsProbe for HostFsProbe {
    fn read_to_string(&self, path: &Path) -> Result<String, String> {
        fs::read_to_string(path).map_err(|err| format!("{}: {err}", path.display()))
    }

    fn exists(&self, path: &Path) -> bool {
        path.exists()
    }

    fn readable(&self, path: &Path) -> bool {
        fs::OpenOptions::new().read(true).open(path).is_ok()
    }

    fn writable(&self, path: &Path) -> bool {
        fs::OpenOptions::new().write(true).open(path).is_ok()
    }
}

/// In-memory filesystem for unit tests.
#[derive(Debug, Default, Clone)]
pub struct MockFs {
    files: HashMap<PathBuf, String>,
    /// path → (exists, readable, writable)
    nodes: HashMap<PathBuf, (bool, bool, bool)>,
}

impl MockFs {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    #[must_use]
    pub fn with_file(mut self, path: impl Into<PathBuf>, contents: impl Into<String>) -> Self {
        let path = path.into();
        self.files.insert(path.clone(), contents.into());
        self.nodes.insert(path, (true, true, false));
        self
    }

    #[must_use]
    pub fn with_node(
        mut self,
        path: impl Into<PathBuf>,
        exists: bool,
        readable: bool,
        writable: bool,
    ) -> Self {
        self.nodes.insert(path.into(), (exists, readable, writable));
        self
    }
}

impl FsProbe for MockFs {
    fn read_to_string(&self, path: &Path) -> Result<String, String> {
        self.files
            .get(path)
            .cloned()
            .ok_or_else(|| format!("{}: No such file (mock)", path.display()))
    }

    fn exists(&self, path: &Path) -> bool {
        self.nodes.get(path).map(|(e, _, _)| *e).unwrap_or(false)
    }

    fn readable(&self, path: &Path) -> bool {
        self.nodes.get(path).map(|(_, r, _)| *r).unwrap_or(false)
    }

    fn writable(&self, path: &Path) -> bool {
        self.nodes.get(path).map(|(_, _, w)| *w).unwrap_or(false)
    }
}

/// Helper used by host OS parsing tests and live checks.
#[must_use]
pub fn parse_os_release_pretty_name(contents: &str) -> Option<String> {
    for line in contents.lines() {
        let line = line.trim();
        if let Some(rest) = line.strip_prefix("PRETTY_NAME=") {
            let value = rest.trim().trim_matches('"');
            if !value.is_empty() {
                return Some(value.to_string());
            }
        }
    }
    None
}

/// Classify an `io::Error` without panicking on unexpected kinds.
#[must_use]
pub fn io_kind_label(err: &io::Error) -> &'static str {
    match err.kind() {
        io::ErrorKind::NotFound => "not found",
        io::ErrorKind::PermissionDenied => "permission denied",
        _ => "error",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_pretty_name() {
        let sample = "NAME=\"Ubuntu\"\nPRETTY_NAME=\"Ubuntu 24.04.5 LTS\"\n";
        assert_eq!(
            parse_os_release_pretty_name(sample).as_deref(),
            Some("Ubuntu 24.04.5 LTS")
        );
    }

    #[test]
    fn parse_pretty_name_missing() {
        assert_eq!(parse_os_release_pretty_name("NAME=Ubuntu\n"), None);
    }

    #[test]
    fn mock_fs_kvm_permissions() {
        let fs = MockFs::new().with_node("/dev/kvm", true, false, false);
        assert!(fs.exists(Path::new("/dev/kvm")));
        assert!(!fs.readable(Path::new("/dev/kvm")));
        assert!(!fs.writable(Path::new("/dev/kvm")));
    }
}
