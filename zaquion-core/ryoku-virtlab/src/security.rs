//! Path and device policy: block physical disks and escape from the lab tree.

use std::fmt;
use std::path::{Component, Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PathRole {
    Disk,
    Kernel,
    /// CD/DVD ISO under fixtures/ or run/ only.
    Iso,
    /// Serial log path under results/ only.
    SerialLog,
}

impl PathRole {
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Disk => "disk",
            Self::Kernel => "kernel",
            Self::Iso => "iso",
            Self::SerialLog => "serial_log",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SecurityError {
    EmptyPath,
    AbsoluteForbidden(String),
    PhysicalDevice(String),
    ParentEscape(String),
    OutsideLab { path: String, lab_root: String },
    Suspicious(String),
}

impl fmt::Display for SecurityError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::EmptyPath => write!(f, "empty path"),
            Self::AbsoluteForbidden(p) => {
                write!(f, "absolute host path not allowed: {p}")
            }
            Self::PhysicalDevice(p) => {
                write!(f, "physical/block device path blocked: {p}")
            }
            Self::ParentEscape(p) => write!(f, "path escapes with `..`: {p}"),
            Self::OutsideLab { path, lab_root } => {
                write!(f, "path `{path}` is outside lab root `{lab_root}`")
            }
            Self::Suspicious(p) => write!(f, "suspicious path rejected: {p}"),
        }
    }
}

impl std::error::Error for SecurityError {}

/// True if `path` looks like a host block device we must never attach.
#[must_use]
pub fn is_blocked_physical_device(path: &str) -> bool {
    let p = path.trim();
    let lower = p.to_ascii_lowercase();

    if lower == "/dev/sda"
        || lower.starts_with("/dev/sda")
        || lower == "/dev/sdb"
        || lower.starts_with("/dev/sdb")
        || lower.starts_with("/dev/sd")
        || lower.starts_with("/dev/nvme")
        || lower.starts_with("/dev/vd")
        || lower.starts_with("/dev/xvd")
        || lower.starts_with("/dev/mmcblk")
        || lower.starts_with("/dev/disk/")
        || lower.starts_with("/dev/mapper/")
        || lower.starts_with("/dev/dm-")
        || lower.starts_with("/dev/loop")
        || lower == "/dev/root"
    {
        return true;
    }

    // Bare names sometimes passed by mistake
    matches!(lower.as_str(), "sda" | "sdb" | "nvme0n1" | "nvme0n1p1")
        || lower.starts_with("nvme") && !lower.contains('/')
}

/// Validate a relative lab asset path and resolve it under `lab_root`.
///
/// Allowed roots (after join + normalize):
/// - Disk / Kernel / Iso → `fixtures/` or `run/`
/// - SerialLog → `results/` only
pub fn validate_optional_path(
    raw: &str,
    role: PathRole,
    lab_root: &Path,
) -> Result<PathBuf, SecurityError> {
    let raw = raw.trim();
    if raw.is_empty() {
        return Err(SecurityError::EmptyPath);
    }
    if is_blocked_physical_device(raw) {
        return Err(SecurityError::PhysicalDevice(raw.to_string()));
    }
    if raw.starts_with('/') || Path::new(raw).is_absolute() {
        // Even absolute paths under lab_root are rejected to keep the policy simple
        // and avoid accidental `/dev/...` or host home paths.
        return Err(SecurityError::AbsoluteForbidden(raw.to_string()));
    }
    if raw.contains('\0') {
        return Err(SecurityError::Suspicious(raw.to_string()));
    }

    let candidate = Path::new(raw);
    if candidate
        .components()
        .any(|c| matches!(c, Component::ParentDir))
    {
        return Err(SecurityError::ParentEscape(raw.to_string()));
    }

    // Lab root must be absolute so lexical `..` popping cannot retarget assets
    // under a different tree (e.g. `../tests/qemu` + join → collapse to `tests/qemu`
    // under `zaquion-core/`).
    let lab_abs = ensure_absolute_lab_root(lab_root)?;
    let joined = lab_abs.join(candidate);
    let normalized = normalize_lexically(&joined);

    let allowed = match role {
        PathRole::SerialLog => vec![normalize_lexically(&lab_abs.join("results"))],
        PathRole::Disk | PathRole::Kernel | PathRole::Iso => vec![
            normalize_lexically(&lab_abs.join("fixtures")),
            normalize_lexically(&lab_abs.join("run")),
        ],
    };

    if !allowed.iter().any(|root| is_under(&normalized, root)) {
        return Err(SecurityError::OutsideLab {
            path: normalized.display().to_string(),
            lab_root: lab_abs.display().to_string(),
        });
    }

    Ok(normalized)
}

fn is_under(path: &Path, root: &Path) -> bool {
    path.starts_with(root)
}

/// Lexical normalization without touching the real filesystem (no symlink resolve).
#[must_use]
pub fn normalize_lexically(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for comp in path.components() {
        match comp {
            Component::ParentDir => {
                out.pop();
            }
            Component::CurDir => {}
            other => out.push(other.as_os_str()),
        }
    }
    out
}

/// Make `path` absolute against `base` (typically the process cwd), then normalize.
///
/// Does **not** call `canonicalize` (no symlink follow). Safe for constructing lab roots
/// before the directory fully exists.
#[must_use]
pub fn absolute_from(base: &Path, path: &Path) -> PathBuf {
    if path.is_absolute() {
        normalize_lexically(path)
    } else {
        normalize_lexically(&base.join(path))
    }
}

/// Ensure `lab_root` is absolute. Relative roots are resolved against the current directory.
fn ensure_absolute_lab_root(lab_root: &Path) -> Result<PathBuf, SecurityError> {
    if lab_root.as_os_str().is_empty() {
        return Err(SecurityError::EmptyPath);
    }
    if lab_root.is_absolute() {
        return Ok(normalize_lexically(lab_root));
    }
    let cwd = std::env::current_dir().map_err(|err| {
        SecurityError::Suspicious(format!("cannot resolve cwd for relative lab_root: {err}"))
    })?;
    Ok(absolute_from(&cwd, lab_root))
}

/// Canonicalize an existing directory. Rejects results that are not directories.
///
/// Used only for lab-root discovery after the path is known to contain `configs/` or
/// `fixtures/`. Does not follow a symlink *out* of policy beyond what the OS returns;
/// callers still constrain assets under `run/` / `fixtures/` / `results/`.
pub fn safe_canonicalize_existing(path: &Path) -> Result<PathBuf, SecurityError> {
    let canon = std::fs::canonicalize(path).map_err(|err| {
        SecurityError::Suspicious(format!("cannot canonicalize `{}`: {err}", path.display()))
    })?;
    if !canon.is_dir() {
        return Err(SecurityError::Suspicious(format!(
            "canonical lab root is not a directory: {}",
            canon.display()
        )));
    }
    Ok(canon)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lab() -> PathBuf {
        PathBuf::from("/workspace/tests/qemu")
    }

    #[test]
    fn blocks_sda_and_nvme() {
        assert!(is_blocked_physical_device("/dev/sda"));
        assert!(is_blocked_physical_device("/dev/sda1"));
        assert!(is_blocked_physical_device("/dev/nvme0n1"));
        assert!(is_blocked_physical_device("/dev/nvme0n1p2"));
        assert!(is_blocked_physical_device("/dev/disk/by-id/foo"));
    }

    #[test]
    fn allows_relative_fixture_disk() {
        let p = validate_optional_path("fixtures/disk.qcow2", PathRole::Disk, &lab()).unwrap();
        assert!(p.ends_with("fixtures/disk.qcow2"));
    }

    #[test]
    fn rejects_parent_escape() {
        let err = validate_optional_path("../etc/passwd", PathRole::Disk, &lab()).unwrap_err();
        assert!(matches!(err, SecurityError::ParentEscape(_)));
    }

    #[test]
    fn rejects_absolute_dev() {
        let err = validate_optional_path("/dev/sda", PathRole::Disk, &lab()).unwrap_err();
        // Physical check happens first for /dev/sda
        assert!(matches!(
            err,
            SecurityError::PhysicalDevice(_) | SecurityError::AbsoluteForbidden(_)
        ));
    }

    #[test]
    fn rejects_path_outside_fixtures_run() {
        let err = validate_optional_path("expectations/x.img", PathRole::Disk, &lab()).unwrap_err();
        assert!(matches!(err, SecurityError::OutsideLab { .. }));
    }

    #[test]
    fn serial_log_must_be_under_results() {
        let ok = validate_optional_path("results/serial.log", PathRole::SerialLog, &lab());
        assert!(ok.is_ok());
        let bad = validate_optional_path("run/serial.log", PathRole::SerialLog, &lab());
        assert!(matches!(bad, Err(SecurityError::OutsideLab { .. })));
    }

    #[test]
    fn absolute_from_preserves_parent_then_normalizes() {
        let abs = absolute_from(Path::new("/repo/zaquion-core"), Path::new("../tests/qemu"));
        assert_eq!(abs, PathBuf::from("/repo/tests/qemu"));
        let iso = validate_optional_path("run/alpine.iso", PathRole::Iso, &abs).unwrap();
        assert_eq!(iso, PathBuf::from("/repo/tests/qemu/run/alpine.iso"));
        assert!(iso.is_absolute());
    }

    #[test]
    fn missing_asset_path_stays_absolute_never_pass_path() {
        let lab = PathBuf::from("/repo/tests/qemu");
        let iso = validate_optional_path("run/missing.iso", PathRole::Iso, &lab).unwrap();
        assert!(iso.is_absolute());
        assert!(!iso.is_file());
        // Path validation succeeded; existence is a separate concern (NOT_RUN/FAIL in boot).
        assert_eq!(iso, PathBuf::from("/repo/tests/qemu/run/missing.iso"));
    }
}
