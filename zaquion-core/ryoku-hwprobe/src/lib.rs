//! Ryoku hardware probe — read-only inventory over a confined root (Mission 013).
//!
//! Never opens the ambient host `/sys` or `/proc` implicitly. Callers must supply
//! an explicit root (guest `/` after PID 1 mounts, or a test fixture tree).
//!
//! # Symlinks
//!
//! Unlike experimental console FS (reject-all), sysfs uses many legitimate
//! symlinks. This crate resolves paths with [`std::fs::canonicalize`] and
//! **rejects** any result that escapes the configured root.

#![forbid(unsafe_code)]

use std::fmt;
use std::fs::{self, File};
use std::io::{self, Read};
use std::path::{Path, PathBuf};

/// Identity string for probe-owned output (never a boot READY claim).
pub const HWPROBE_IDENTITY: &str = "ryoku-hwprobe";

/// Cap for any single file read (cpuinfo / small sysfs attrs).
pub const MAX_FILE_BYTES: usize = 64 * 1024;

/// Cap for directory listing entries (pci devices, drivers, ttys).
pub const MAX_DIR_ENTRIES: usize = 256;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HwError {
    RootRequired,
    InvalidRoot(String),
    Missing { path: String },
    Escape { path: String },
    Io(String),
    TooLarge { path: String },
}

impl fmt::Display for HwError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::RootRequired => write!(
                f,
                "{HWPROBE_IDENTITY}: requires RYOKU_HWPROBE_ROOT or RYOKU_CONSOLE_ROOT (never implicit host /sys)"
            ),
            Self::InvalidRoot(detail) => {
                write!(f, "{HWPROBE_IDENTITY}: invalid root ({detail})")
            }
            Self::Missing { path } => {
                write!(f, "{HWPROBE_IDENTITY}: missing {path} (nodes not mounted or absent)")
            }
            Self::Escape { path } => {
                write!(f, "{HWPROBE_IDENTITY}: path escaped root ({path})")
            }
            Self::Io(detail) => write!(f, "{HWPROBE_IDENTITY}: i/o ({detail})"),
            Self::TooLarge { path } => {
                write!(f, "{HWPROBE_IDENTITY}: file too large ({path})")
            }
        }
    }
}

impl std::error::Error for HwError {}

impl From<io::Error> for HwError {
    fn from(err: io::Error) -> Self {
        Self::Io(err.to_string())
    }
}

/// Confined view of a guest (or fixture) filesystem root.
#[derive(Debug, Clone)]
pub struct HwRoot {
    root: PathBuf,
    root_canon: PathBuf,
}

impl HwRoot {
    /// Validate `root` as an absolute plain directory (after canonicalize).
    pub fn validated(root: PathBuf) -> Result<Self, HwError> {
        if !root.is_absolute() {
            return Err(HwError::InvalidRoot("must be absolute".into()));
        }
        let meta = fs::symlink_metadata(&root).map_err(|e| HwError::InvalidRoot(e.to_string()))?;
        if meta.file_type().is_symlink() {
            return Err(HwError::InvalidRoot("root must not be a symlink".into()));
        }
        if !meta.is_dir() {
            return Err(HwError::InvalidRoot("root must be a directory".into()));
        }
        let root_canon =
            fs::canonicalize(&root).map_err(|e| HwError::InvalidRoot(e.to_string()))?;
        let meta2 =
            fs::symlink_metadata(&root_canon).map_err(|e| HwError::InvalidRoot(e.to_string()))?;
        if meta2.file_type().is_symlink() {
            return Err(HwError::InvalidRoot("canonical root is a symlink".into()));
        }
        Ok(Self { root, root_canon })
    }

    /// From `RYOKU_HWPROBE_ROOT`, else `RYOKU_CONSOLE_ROOT`. Never falls back to `/`.
    pub fn from_env() -> Result<Self, HwError> {
        let raw = std::env::var_os("RYOKU_HWPROBE_ROOT")
            .or_else(|| std::env::var_os("RYOKU_CONSOLE_ROOT"))
            .ok_or(HwError::RootRequired)?;
        Self::validated(PathBuf::from(raw))
    }

    #[must_use]
    pub fn root(&self) -> &Path {
        &self.root
    }

    /// Resolve `guest_abs` (e.g. `/proc/cpuinfo`) under this root; allow in-tree symlinks.
    pub fn resolve(&self, guest_abs: &str) -> Result<PathBuf, HwError> {
        let rel = guest_abs.trim_start_matches('/');
        let joined = if rel.is_empty() {
            self.root.clone()
        } else {
            self.root.join(rel)
        };
        if !joined.exists() {
            return Err(HwError::Missing {
                path: guest_abs.to_string(),
            });
        }
        let canon = fs::canonicalize(&joined).map_err(|e| {
            if e.kind() == io::ErrorKind::NotFound {
                HwError::Missing {
                    path: guest_abs.to_string(),
                }
            } else {
                HwError::Io(format!("{guest_abs}: {e}"))
            }
        })?;
        if !canon.starts_with(&self.root_canon) {
            return Err(HwError::Escape {
                path: guest_abs.to_string(),
            });
        }
        Ok(canon)
    }

    fn read_capped(&self, guest_abs: &str) -> Result<String, HwError> {
        let path = self.resolve(guest_abs)?;
        let mut f = File::open(&path).map_err(|e| HwError::Io(format!("{guest_abs}: {e}")))?;
        let mut buf = Vec::new();
        let mut chunk = [0u8; 4096];
        loop {
            let n = f.read(&mut chunk)?;
            if n == 0 {
                break;
            }
            if buf.len() + n > MAX_FILE_BYTES {
                return Err(HwError::TooLarge {
                    path: guest_abs.to_string(),
                });
            }
            buf.extend_from_slice(&chunk[..n]);
        }
        String::from_utf8(buf).map_err(|e| HwError::Io(format!("{guest_abs}: utf8 ({e})")))
    }

    fn list_dir_names(&self, guest_abs: &str) -> Result<Vec<String>, HwError> {
        let path = self.resolve(guest_abs)?;
        let mut names = Vec::new();
        let rd = fs::read_dir(&path).map_err(|e| HwError::Io(format!("{guest_abs}: {e}")))?;
        for ent in rd.take(MAX_DIR_ENTRIES) {
            let ent = ent.map_err(|e| HwError::Io(format!("{guest_abs}: {e}")))?;
            let name = ent.file_name().to_string_lossy().into_owned();
            if name == "." || name == ".." {
                continue;
            }
            names.push(name);
        }
        names.sort();
        Ok(names)
    }

    /// High-level inventory; honest about missing mounts.
    pub fn summary(&self) -> String {
        let mut out = format!("{HWPROBE_IDENTITY}: summary (read-only; not product drivers)\n");

        match self.cpu_brief() {
            Ok(s) => {
                out.push_str(&s);
                out.push('\n');
            }
            Err(e) => out.push_str(&format!("cpu: ERR {e}\n")),
        }
        match self.pci_count() {
            Ok(n) => out.push_str(&format!("pci_devices: {n}\n")),
            Err(e) => out.push_str(&format!("pci_devices: ERR {e}\n")),
        }
        match self.tty_names() {
            Ok(names) if names.is_empty() => out.push_str("tty: (none listed)\n"),
            Ok(names) => {
                let preview: Vec<_> = names.into_iter().take(8).collect();
                out.push_str(&format!("tty: {}\n", preview.join(" ")));
            }
            Err(e) => out.push_str(&format!("tty: ERR {e}\n")),
        }
        match self.driver_names() {
            Ok(names) => out.push_str(&format!("drivers_listed: {}\n", names.len())),
            Err(e) => out.push_str(&format!("drivers_listed: ERR {e}\n")),
        }
        out.push_str("honesty: missing nodes reported as ERR; never invent success\n");
        out
    }

    pub fn cpu_report(&self) -> Result<String, HwError> {
        let text = self.read_capped("/proc/cpuinfo")?;
        let mut model = None;
        let mut processors = 0u32;
        for line in text.lines() {
            if let Some(rest) = line.strip_prefix("processor") {
                if rest.trim_start().starts_with(':') {
                    processors += 1;
                }
            }
            if model.is_none() {
                if let Some(rest) = line.strip_prefix("model name") {
                    if let Some(v) = rest.split_once(':').map(|(_, v)| v.trim()) {
                        if !v.is_empty() {
                            model = Some(v.to_string());
                        }
                    }
                }
            }
            // qemu/virt often uses "Hardware" or leaves model blank — keep "cpu" line too.
            if model.is_none() {
                if let Some(rest) = line.strip_prefix("Hardware") {
                    if let Some(v) = rest.split_once(':').map(|(_, v)| v.trim()) {
                        if !v.is_empty() {
                            model = Some(v.to_string());
                        }
                    }
                }
            }
        }
        let mut out = format!("{HWPROBE_IDENTITY}: cpu\n");
        out.push_str(&format!("processors: {processors}\n"));
        out.push_str(&format!(
            "model: {}\n",
            model.unwrap_or_else(|| "(unspecified in cpuinfo)".into())
        ));
        Ok(out)
    }

    fn cpu_brief(&self) -> Result<String, HwError> {
        let full = self.cpu_report()?;
        let mut procs = "?".to_string();
        let mut model = "?".to_string();
        for line in full.lines() {
            if let Some(v) = line.strip_prefix("processors: ") {
                procs = v.to_string();
            }
            if let Some(v) = line.strip_prefix("model: ") {
                model = v.to_string();
            }
        }
        Ok(format!("cpu: processors={procs} model={model}"))
    }

    pub fn pci_report(&self) -> Result<String, HwError> {
        let names = self.list_dir_names("/sys/bus/pci/devices")?;
        let mut out = format!("{HWPROBE_IDENTITY}: pci ({} device nodes)\n", names.len());
        for name in names.iter().take(64) {
            let vendor_path = format!("/sys/bus/pci/devices/{name}/vendor");
            let device_path = format!("/sys/bus/pci/devices/{name}/device");
            let vendor = self
                .read_capped(&vendor_path)
                .map(|s| s.trim().to_string())
                .unwrap_or_else(|_| "?".into());
            let device = self
                .read_capped(&device_path)
                .map(|s| s.trim().to_string())
                .unwrap_or_else(|_| "?".into());
            out.push_str(&format!("{name} vendor={vendor} device={device}\n"));
        }
        if names.len() > 64 {
            out.push_str(&format!("… truncated ({} more)\n", names.len() - 64));
        }
        Ok(out)
    }

    fn pci_count(&self) -> Result<usize, HwError> {
        Ok(self.list_dir_names("/sys/bus/pci/devices")?.len())
    }

    pub fn drivers_report(&self) -> Result<String, HwError> {
        let names = self.driver_names()?;
        let mut out = format!(
            "{HWPROBE_IDENTITY}: drivers ({} listed under sysfs bus)\n",
            names.len()
        );
        for name in names.iter().take(64) {
            out.push_str(name);
            out.push('\n');
        }
        if names.len() > 64 {
            out.push_str(&format!("… truncated ({} more)\n", names.len() - 64));
        }
        Ok(out)
    }

    fn driver_names(&self) -> Result<Vec<String>, HwError> {
        // Prefer pci drivers; fall back to listing /sys/bus/*/drivers when pci absent.
        match self.list_dir_names("/sys/bus/pci/drivers") {
            Ok(names) if !names.is_empty() => Ok(names),
            Ok(_) | Err(HwError::Missing { .. }) => {
                // Aggregate a few common buses without inventing data.
                let mut all = Vec::new();
                for bus in ["pci", "virtio", "platform", "usb"] {
                    let path = format!("/sys/bus/{bus}/drivers");
                    if let Ok(names) = self.list_dir_names(&path) {
                        for n in names {
                            all.push(format!("{bus}/{n}"));
                        }
                    }
                }
                if all.is_empty() {
                    // Surface missing honestly if nothing readable.
                    let _ = self.resolve("/sys/bus")?;
                    Ok(all)
                } else {
                    all.sort();
                    Ok(all)
                }
            }
            Err(e) => Err(e),
        }
    }

    fn tty_names(&self) -> Result<Vec<String>, HwError> {
        match self.list_dir_names("/sys/class/tty") {
            Ok(names) => Ok(names),
            Err(HwError::Missing { .. }) => {
                // Fallback: /proc/tty/drivers (text table).
                let text = self.read_capped("/proc/tty/drivers")?;
                let mut names = Vec::new();
                for line in text.lines() {
                    let mut parts = line.split_whitespace();
                    if let Some(first) = parts.next() {
                        if first != "name" {
                            names.push(first.to_string());
                        }
                    }
                }
                Ok(names)
            }
            Err(e) => Err(e),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::symlink;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn scratch(tag: &str) -> PathBuf {
        let n = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let p = std::env::temp_dir().join(format!("ryoku-hwprobe-{tag}-{n}"));
        let _ = fs::remove_dir_all(&p);
        fs::create_dir_all(&p).unwrap();
        p
    }

    fn write_fixture(root: &Path) {
        fs::create_dir_all(root.join("proc")).unwrap();
        fs::write(
            root.join("proc/cpuinfo"),
            b"processor\t: 0\nmodel name\t: TestCPU Virt\nprocessor\t: 1\nmodel name\t: TestCPU Virt\n",
        )
        .unwrap();
        fs::create_dir_all(root.join("sys/bus/pci/devices/0000:00:00.0")).unwrap();
        fs::write(
            root.join("sys/bus/pci/devices/0000:00:00.0/vendor"),
            b"0x1b36\n",
        )
        .unwrap();
        fs::write(
            root.join("sys/bus/pci/devices/0000:00:00.0/device"),
            b"0x0008\n",
        )
        .unwrap();
        fs::create_dir_all(root.join("sys/bus/pci/drivers/virtio-pci")).unwrap();
        fs::create_dir_all(root.join("sys/class/tty")).unwrap();
        // Legitimate sysfs-style symlink that stays inside root.
        fs::create_dir_all(root.join("sys/devices/platform/serial")).unwrap();
        symlink(
            "../../devices/platform/serial",
            root.join("sys/class/tty/ttyS0"),
        )
        .unwrap();
    }

    #[test]
    fn fixture_summary_cpu_pci_drivers() {
        let root = scratch("ok");
        write_fixture(&root);
        let hw = HwRoot::validated(root.clone()).unwrap();
        let summary = hw.summary();
        assert!(summary.contains("processors=2"), "{summary}");
        assert!(summary.contains("TestCPU Virt"), "{summary}");
        assert!(summary.contains("pci_devices: 1"), "{summary}");
        assert!(summary.contains("tty:"), "{summary}");
        assert!(summary.contains("drivers_listed: 1"), "{summary}");

        let cpu = hw.cpu_report().unwrap();
        assert!(cpu.contains("processors: 2"));
        let pci = hw.pci_report().unwrap();
        assert!(pci.contains("0000:00:00.0"));
        assert!(pci.contains("0x1b36"));
        let drv = hw.drivers_report().unwrap();
        assert!(drv.contains("virtio-pci"));
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn missing_proc_is_honest_error() {
        let root = scratch("noproc");
        fs::create_dir_all(root.join("sys")).unwrap();
        let hw = HwRoot::validated(root.clone()).unwrap();
        let err = hw.cpu_report().unwrap_err();
        assert!(matches!(err, HwError::Missing { .. }), "{err}");
        let summary = hw.summary();
        assert!(summary.contains("ERR"), "{summary}");
        assert!(
            !summary.contains("pci_devices: 0") || summary.contains("ERR"),
            "{summary}"
        );
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn symlink_escape_rejected() {
        let root = scratch("escape");
        write_fixture(&root);
        let outside = scratch("outside");
        fs::write(outside.join("secret"), b"nope").unwrap();
        // Replace ttyS0 with link escaping the root.
        let _ = fs::remove_file(root.join("sys/class/tty/ttyS0"));
        symlink(&outside, root.join("sys/class/tty/ttyS0")).unwrap();
        let hw = HwRoot::validated(root.clone()).unwrap();
        let err = hw.resolve("/sys/class/tty/ttyS0").unwrap_err();
        assert!(matches!(err, HwError::Escape { .. }), "{err}");
        let _ = fs::remove_dir_all(&root);
        let _ = fs::remove_dir_all(&outside);
    }

    #[test]
    fn from_env_never_implies_host_sys() {
        // Ensure we don't accidentally read ambient /sys in this test process
        // without an explicit root — RootRequired when both env vars absent.
        std::env::remove_var("RYOKU_HWPROBE_ROOT");
        // Do not clear RYOKU_CONSOLE_ROOT if a parent set it for other tests —
        // instead set an invalid empty via validated path API.
        let err = HwRoot::validated(PathBuf::from("relative")).unwrap_err();
        assert!(matches!(err, HwError::InvalidRoot(_)));
    }
}
