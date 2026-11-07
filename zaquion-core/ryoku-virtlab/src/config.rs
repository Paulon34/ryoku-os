//! Minimal line-oriented VM config (stdlib-only; no TOML/JSON crates).

use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};

use crate::security::{validate_optional_path, PathRole, SecurityError};

/// Acceleration preference for QEMU.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AccelMode {
    /// Prefer KVM when `/dev/kvm` is usable; otherwise TCG.
    Auto,
    /// Force software emulation (`-accel tcg`).
    Tcg,
    /// Require KVM (`-accel kvm`); fail validation if unavailable at T1 time.
    Kvm,
}

impl AccelMode {
    fn parse(raw: &str) -> Result<Self, ConfigError> {
        match raw {
            "auto" => Ok(Self::Auto),
            "tcg" => Ok(Self::Tcg),
            "kvm" => Ok(Self::Kvm),
            other => Err(ConfigError::InvalidValue {
                key: "accel",
                value: other.to_string(),
            }),
        }
    }

    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Auto => "auto",
            Self::Tcg => "tcg",
            Self::Kvm => "kvm",
        }
    }
}

/// Guest network mode. Default is isolated (`none`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NetworkMode {
    None,
}

impl NetworkMode {
    fn parse(raw: &str) -> Result<Self, ConfigError> {
        match raw {
            "none" => Ok(Self::None),
            other => Err(ConfigError::InvalidValue {
                key: "network",
                value: other.to_string(),
            }),
        }
    }
}

/// Validated Virtual Lab VM configuration.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VmConfig {
    pub name: String,
    pub memory_mb: u32,
    pub cpus: u32,
    pub timeout_secs: u64,
    pub accel: AccelMode,
    pub network: NetworkMode,
    /// Guest disk image path, or `None` for emulator-only smoke (no OS boot claim).
    pub disk: Option<PathBuf>,
    /// Guest kernel path, or `None`.
    pub kernel: Option<PathBuf>,
    /// Guest initrd/initramfs path under `run/` or `fixtures/`, or `None`.
    pub initrd: Option<PathBuf>,
    /// Optional kernel command line (`-append`), e.g. `console=ttyS0`.
    pub append: Option<String>,
    /// Optional ISO/CD image under `run/` or `fixtures/` (reference Linux).
    pub iso: Option<PathBuf>,
    /// Optional serial log file under `results/`.
    pub serial_log: Option<PathBuf>,
    /// Substring that must appear in serial output to claim reference guest console progress.
    pub boot_sentinel: Option<String>,
    /// Additional required serial substrings. All must match for PASS.
    /// Configured as a single `|`-separated line: `boot_markers = Alpine|login:`
    pub boot_markers: Vec<String>,
    pub shutdown: ShutdownMode,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ConfigError {
    Io(String),
    Parse(String),
    MissingKey(&'static str),
    InvalidValue {
        key: &'static str,
        value: String,
    },
    Security(SecurityError),
    Limits {
        field: &'static str,
        message: String,
    },
}

impl fmt::Display for ConfigError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Io(msg) => write!(f, "io: {msg}"),
            Self::Parse(msg) => write!(f, "parse: {msg}"),
            Self::MissingKey(key) => write!(f, "missing key `{key}`"),
            Self::InvalidValue { key, value } => {
                write!(f, "invalid value for `{key}`: {value}")
            }
            Self::Security(err) => write!(f, "security: {err}"),
            Self::Limits { field, message } => write!(f, "limits ({field}): {message}"),
        }
    }
}

impl std::error::Error for ConfigError {}

impl From<SecurityError> for ConfigError {
    fn from(value: SecurityError) -> Self {
        Self::Security(value)
    }
}

/// How to request a clean guest/emulator stop after the run window.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ShutdownMode {
    /// Send QEMU monitor `quit` on stdin (works with `-monitor stdio`).
    MonitorQuit,
    /// Rely on timeout kill only (no monitor input).
    None,
}

impl ShutdownMode {
    fn parse(raw: &str) -> Result<Self, ConfigError> {
        match raw {
            "monitor_quit" => Ok(Self::MonitorQuit),
            "none" => Ok(Self::None),
            other => Err(ConfigError::InvalidValue {
                key: "shutdown",
                value: other.to_string(),
            }),
        }
    }

    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::MonitorQuit => "monitor_quit",
            Self::None => "none",
        }
    }
}

/// Default hard caps (CPU / RAM / time) for disposable lab VMs.
pub const MAX_MEMORY_MB: u32 = 2048;
pub const MAX_CPUS: u32 = 4;
/// First-boot TCG guests may need several minutes; still capped.
pub const MAX_TIMEOUT_SECS: u64 = 600;
pub const MIN_MEMORY_MB: u32 = 64;
pub const MIN_CPUS: u32 = 1;
pub const MIN_TIMEOUT_SECS: u64 = 1;

impl VmConfig {
    /// Parse and validate a config file under the lab tree.
    pub fn load_file(path: &Path, lab_root: &Path) -> Result<Self, ConfigError> {
        let text = fs::read_to_string(path)
            .map_err(|err| ConfigError::Io(format!("{}: {err}", path.display())))?;
        Self::parse(&text, lab_root)
    }

    /// Parse config text. `lab_root` is typically `tests/qemu`.
    pub fn parse(text: &str, lab_root: &Path) -> Result<Self, ConfigError> {
        let mut name: Option<String> = None;
        let mut memory_mb: Option<u32> = None;
        let mut cpus: Option<u32> = None;
        let mut timeout_secs: Option<u64> = None;
        let mut accel = AccelMode::Auto;
        let mut network = NetworkMode::None;
        let mut disk_raw: Option<String> = None;
        let mut kernel_raw: Option<String> = None;
        let mut initrd_raw: Option<String> = None;
        let mut append: Option<String> = None;
        let mut iso_raw: Option<String> = None;
        let mut serial_raw: Option<String> = None;
        let mut boot_sentinel: Option<String> = None;
        let mut boot_markers: Vec<String> = Vec::new();
        let mut shutdown = ShutdownMode::MonitorQuit;

        for (lineno, raw_line) in text.lines().enumerate() {
            let line = raw_line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let Some((key, value)) = line.split_once('=') else {
                return Err(ConfigError::Parse(format!(
                    "line {}: expected `key = value`, got `{raw_line}`",
                    lineno + 1
                )));
            };
            let key = key.trim();
            let value = value.trim();
            if value.is_empty() {
                return Err(ConfigError::Parse(format!(
                    "line {}: empty value for `{key}`",
                    lineno + 1
                )));
            }
            match key {
                "name" => name = Some(value.to_string()),
                "memory_mb" => {
                    memory_mb = Some(parse_u32(value, "memory_mb")?);
                }
                "cpus" => cpus = Some(parse_u32(value, "cpus")?),
                "timeout_secs" => {
                    timeout_secs = Some(parse_u64(value, "timeout_secs")?);
                }
                "accel" => accel = AccelMode::parse(value)?,
                "network" => network = NetworkMode::parse(value)?,
                "disk" => disk_raw = Some(value.to_string()),
                "kernel" => kernel_raw = Some(value.to_string()),
                "initrd" => initrd_raw = Some(value.to_string()),
                "append" => append = Some(value.to_string()),
                "iso" => iso_raw = Some(value.to_string()),
                "serial_log" => serial_raw = Some(value.to_string()),
                "boot_sentinel" => boot_sentinel = Some(value.to_string()),
                "boot_markers" => {
                    boot_markers = value
                        .split('|')
                        .map(str::trim)
                        .filter(|s| !s.is_empty())
                        .map(str::to_string)
                        .collect();
                }
                "shutdown" => shutdown = ShutdownMode::parse(value)?,
                other => {
                    return Err(ConfigError::Parse(format!(
                        "line {}: unknown key `{other}`",
                        lineno + 1
                    )));
                }
            }
        }

        let name = name.ok_or(ConfigError::MissingKey("name"))?;
        let memory_mb = memory_mb.ok_or(ConfigError::MissingKey("memory_mb"))?;
        let cpus = cpus.ok_or(ConfigError::MissingKey("cpus"))?;
        let timeout_secs = timeout_secs.ok_or(ConfigError::MissingKey("timeout_secs"))?;

        enforce_limits(memory_mb, cpus, timeout_secs)?;

        let disk = parse_optional_asset(disk_raw.as_deref(), PathRole::Disk, lab_root)?;
        let kernel = parse_optional_asset(kernel_raw.as_deref(), PathRole::Kernel, lab_root)?;
        let initrd = parse_optional_asset(initrd_raw.as_deref(), PathRole::Kernel, lab_root)?;
        let iso = parse_optional_asset(iso_raw.as_deref(), PathRole::Iso, lab_root)?;
        let serial_log =
            parse_optional_asset(serial_raw.as_deref(), PathRole::SerialLog, lab_root)?;

        Ok(Self {
            name,
            memory_mb,
            cpus,
            timeout_secs,
            accel,
            network,
            disk,
            kernel,
            initrd,
            append,
            iso,
            serial_log,
            boot_sentinel,
            boot_markers,
            shutdown,
        })
    }

    /// Markers that must all appear in serial text for a verified reference boot PASS.
    /// Prefer `boot_markers` when set; otherwise fall back to a single `boot_sentinel`.
    #[must_use]
    pub fn required_boot_markers(&self) -> Vec<String> {
        if !self.boot_markers.is_empty() {
            return self.boot_markers.clone();
        }
        self.boot_sentinel.iter().cloned().collect()
    }

    /// True when this config cannot claim a guest OS boot (no disk/kernel/iso/initrd).
    #[must_use]
    pub fn is_emulator_only(&self) -> bool {
        self.disk.is_none() && self.kernel.is_none() && self.initrd.is_none() && self.iso.is_none()
    }

    /// True when a reference/guest boot medium is configured (file may still be missing).
    #[must_use]
    pub fn has_boot_medium(&self) -> bool {
        self.disk.is_some() || self.kernel.is_some() || self.initrd.is_some() || self.iso.is_some()
    }
}

fn parse_optional_asset(
    raw: Option<&str>,
    role: PathRole,
    lab_root: &Path,
) -> Result<Option<PathBuf>, ConfigError> {
    match raw {
        None | Some("none") => Ok(None),
        Some(path) => {
            let validated = validate_optional_path(path, role, lab_root)?;
            Ok(Some(validated))
        }
    }
}

fn parse_u32(raw: &str, key: &'static str) -> Result<u32, ConfigError> {
    raw.parse::<u32>().map_err(|_| ConfigError::InvalidValue {
        key,
        value: raw.to_string(),
    })
}

fn parse_u64(raw: &str, key: &'static str) -> Result<u64, ConfigError> {
    raw.parse::<u64>().map_err(|_| ConfigError::InvalidValue {
        key,
        value: raw.to_string(),
    })
}

fn enforce_limits(memory_mb: u32, cpus: u32, timeout_secs: u64) -> Result<(), ConfigError> {
    if !(MIN_MEMORY_MB..=MAX_MEMORY_MB).contains(&memory_mb) {
        return Err(ConfigError::Limits {
            field: "memory_mb",
            message: format!("must be {MIN_MEMORY_MB}..={MAX_MEMORY_MB}, got {memory_mb}"),
        });
    }
    if !(MIN_CPUS..=MAX_CPUS).contains(&cpus) {
        return Err(ConfigError::Limits {
            field: "cpus",
            message: format!("must be {MIN_CPUS}..={MAX_CPUS}, got {cpus}"),
        });
    }
    if !(MIN_TIMEOUT_SECS..=MAX_TIMEOUT_SECS).contains(&timeout_secs) {
        return Err(ConfigError::Limits {
            field: "timeout_secs",
            message: format!("must be {MIN_TIMEOUT_SECS}..={MAX_TIMEOUT_SECS}, got {timeout_secs}"),
        });
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    fn lab() -> &'static Path {
        Path::new("/workspace/tests/qemu")
    }

    #[test]
    fn parses_emulator_only_config() {
        let text = "\
name = smoke
memory_mb = 256
cpus = 1
timeout_secs = 15
accel = tcg
network = none
disk = none
kernel = none
";
        let cfg = VmConfig::parse(text, lab()).unwrap();
        assert_eq!(cfg.name, "smoke");
        assert!(cfg.is_emulator_only());
        assert_eq!(cfg.accel, AccelMode::Tcg);
    }

    #[test]
    fn rejects_unknown_key() {
        let text = "\
name = x
memory_mb = 256
cpus = 1
timeout_secs = 10
weird = 1
";
        assert!(VmConfig::parse(text, lab()).is_err());
    }

    #[test]
    fn rejects_memory_over_cap() {
        let text = "\
name = x
memory_mb = 99999
cpus = 1
timeout_secs = 10
";
        let err = VmConfig::parse(text, lab()).unwrap_err();
        assert!(matches!(
            err,
            ConfigError::Limits {
                field: "memory_mb",
                ..
            }
        ));
    }

    #[test]
    fn parses_boot_markers_pipe_list() {
        let text = "\
name = alpine
memory_mb = 512
cpus = 1
timeout_secs = 180
accel = tcg
network = none
disk = none
kernel = none
iso = run/alpine-virt-3.21.9-x86_64.iso
serial_log = results/serial-t2-reference-alpine.log
boot_sentinel = login:
boot_markers = Alpine|login:
shutdown = monitor_quit
";
        let cfg = VmConfig::parse(text, lab()).unwrap();
        assert_eq!(
            cfg.boot_markers,
            vec!["Alpine".to_string(), "login:".to_string()]
        );
        assert!(cfg.initrd.is_none());
        assert!(cfg.append.is_none());
    }

    #[test]
    fn parses_kernel_initrd_append_boot_seed() {
        let text = "\
name = t3-boot-seed
memory_mb = 256
cpus = 1
timeout_secs = 120
accel = tcg
network = none
disk = none
kernel = run/ryoku-boot-seed-vmlinuz
initrd = run/ryoku-boot-seed.cpio.gz
append = console=ttyS0 earlyprintk=serial
iso = none
serial_log = results/serial-t3-boot-seed.log
boot_markers = ryoku-init: pid=1|RYOKU_BOOT_SEED_READY
shutdown = monitor_quit
";
        let cfg = VmConfig::parse(text, lab()).unwrap();
        assert_eq!(
            cfg.boot_markers,
            vec![
                "ryoku-init: pid=1".to_string(),
                "RYOKU_BOOT_SEED_READY".to_string()
            ]
        );
        assert!(cfg
            .kernel
            .as_ref()
            .unwrap()
            .ends_with("ryoku-boot-seed-vmlinuz"));
        assert!(cfg
            .initrd
            .as_ref()
            .unwrap()
            .ends_with("ryoku-boot-seed.cpio.gz"));
        assert_eq!(
            cfg.append.as_deref(),
            Some("console=ttyS0 earlyprintk=serial")
        );
        assert!(cfg.has_boot_medium());
        assert!(!cfg.is_emulator_only());
    }

    #[test]
    fn rejects_initrd_path_escape() {
        let text = "\
name = bad
memory_mb = 256
cpus = 1
timeout_secs = 30
accel = tcg
network = none
initrd = ../../etc/passwd
";
        assert!(VmConfig::parse(text, lab()).is_err());
    }

    #[test]
    fn rejects_absolute_initrd() {
        let text = "\
name = bad
memory_mb = 256
cpus = 1
timeout_secs = 30
accel = tcg
network = none
initrd = /lib/modules/vmlinuz
";
        assert!(VmConfig::parse(text, lab()).is_err());
    }
}
