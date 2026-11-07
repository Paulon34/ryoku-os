//! Optional experimental filesystem view for Ryoku Minimal (Mission 012).
//!
//! Confines `pwd` / `ls` / `cat` to a staged root. No writes, no mounts, no
//! persistence. Host unit tests use a temp root; the guest uses `/`.

#![forbid(unsafe_code)]

use std::fs;
use std::io::Read;
use std::path::{Component, Path, PathBuf};

/// Hard cap for `cat` payload (bytes).
pub const MAX_CAT_BYTES: usize = 65_536;

/// Max directory entries returned by `ls` (fail closed beyond).
pub const MAX_LS_ENTRIES: usize = 256;

/// Errors from confined FS operations.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FsError {
    Escape,
    NotFound,
    NotDir,
    IsDir,
    TooLarge { size: u64 },
    TooManyEntries { count: usize },
    Io(String),
    InvalidPath,
}

impl std::fmt::Display for FsError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Escape => write!(f, "path escapes experimental root"),
            Self::NotFound => write!(f, "no such file or directory"),
            Self::NotDir => write!(f, "not a directory"),
            Self::IsDir => write!(f, "is a directory"),
            Self::TooLarge { size } => {
                write!(f, "file too large ({size} > {MAX_CAT_BYTES})")
            }
            Self::TooManyEntries { count } => {
                write!(
                    f,
                    "directory listing too large ({count} > {MAX_LS_ENTRIES})"
                )
            }
            Self::Io(msg) => write!(f, "io: {msg}"),
            Self::InvalidPath => write!(f, "invalid path"),
        }
    }
}

impl std::error::Error for FsError {}

/// Confined guest/host experimental filesystem cursor.
#[derive(Debug, Clone)]
pub struct GuestFs {
    /// Absolute host path that acts as guest `/`.
    root: PathBuf,
    /// Logical cwd inside the guest (`/`-prefixed, no `..`).
    cwd: String,
}

impl GuestFs {
    /// Create a view rooted at `root` with logical cwd `/home/ryoku` when that
    /// directory exists under root, otherwise `/`.
    #[must_use]
    pub fn new(root: PathBuf) -> Self {
        let mut fs = Self {
            root,
            cwd: "/".to_string(),
        };
        if fs.root.join("home/ryoku").is_dir() {
            fs.cwd = "/home/ryoku".to_string();
        }
        fs
    }

    /// Guest root `/` (initramfs). Prefer for real guest processes.
    #[must_use]
    pub fn guest_root() -> Self {
        Self::new(PathBuf::from("/"))
    }

    #[must_use]
    pub fn root(&self) -> &Path {
        &self.root
    }

    #[must_use]
    pub fn cwd(&self) -> &str {
        &self.cwd
    }

    /// Logical `pwd` (always `/`-prefixed guest path).
    #[must_use]
    pub fn pwd(&self) -> String {
        format!("{}\n", self.cwd)
    }

    /// Resolve a user path to a host path under `root` (no escape).
    pub fn resolve(&self, user_path: &str) -> Result<(String, PathBuf), FsError> {
        if user_path.is_empty() || user_path.contains('\0') {
            return Err(FsError::InvalidPath);
        }
        let logical = if user_path.starts_with('/') {
            normalize_logical(user_path)?
        } else {
            let joined = if self.cwd == "/" {
                format!("/{user_path}")
            } else {
                format!("{}/{user_path}", self.cwd.trim_end_matches('/'))
            };
            normalize_logical(&joined)?
        };
        let rel = logical.trim_start_matches('/');
        let host = if rel.is_empty() {
            self.root.clone()
        } else {
            self.root.join(rel)
        };
        // Defense in depth: components under root must not contain ParentDir after join.
        for c in host
            .strip_prefix(&self.root)
            .unwrap_or(host.as_path())
            .components()
        {
            if matches!(c, Component::ParentDir) {
                return Err(FsError::Escape);
            }
        }
        Ok((logical, host))
    }

    /// List a directory (default: cwd). Names only, one per line, sorted.
    pub fn ls(&self, path: Option<&str>) -> Result<String, FsError> {
        let user = path.unwrap_or(".");
        let (_logical, host) = self.resolve(user)?;
        let meta = fs::metadata(&host).map_err(map_io)?;
        if !meta.is_dir() {
            return Err(FsError::NotDir);
        }
        let mut names = Vec::new();
        let rd = fs::read_dir(&host).map_err(map_io)?;
        for ent in rd {
            let ent = ent.map_err(map_io)?;
            let name = ent.file_name();
            let s = name.to_string_lossy();
            if s == "." || s == ".." {
                continue;
            }
            // Reject non-ASCII names in listings (parser is ASCII-only elsewhere).
            if !s.is_ascii() {
                continue;
            }
            names.push(s.into_owned());
            if names.len() > MAX_LS_ENTRIES {
                return Err(FsError::TooManyEntries { count: names.len() });
            }
        }
        names.sort_unstable();
        if names.is_empty() {
            return Ok(String::new());
        }
        Ok(format!("{}\n", names.join("\n")))
    }

    /// Read a regular file (capped).
    pub fn cat(&self, path: &str) -> Result<String, FsError> {
        let (_logical, host) = self.resolve(path)?;
        let meta = fs::metadata(&host).map_err(map_io)?;
        if meta.is_dir() {
            return Err(FsError::IsDir);
        }
        if !meta.is_file() {
            return Err(FsError::NotFound);
        }
        let size = meta.len();
        if size > MAX_CAT_BYTES as u64 {
            return Err(FsError::TooLarge { size });
        }
        let mut f = fs::File::open(&host).map_err(map_io)?;
        let mut buf = Vec::with_capacity(size as usize);
        f.read_to_end(&mut buf).map_err(map_io)?;
        if buf.len() > MAX_CAT_BYTES {
            return Err(FsError::TooLarge {
                size: buf.len() as u64,
            });
        }
        // Lossy only for display; reject NULs.
        if buf.contains(&0) {
            return Err(FsError::Io("NUL in file".into()));
        }
        match String::from_utf8(buf) {
            Ok(s) => {
                if s.ends_with('\n') {
                    Ok(s)
                } else {
                    Ok(format!("{s}\n"))
                }
            }
            Err(_) => Err(FsError::Io("non-UTF-8 file".into())),
        }
    }
}

fn map_io(err: std::io::Error) -> FsError {
    if err.kind() == std::io::ErrorKind::NotFound {
        FsError::NotFound
    } else {
        FsError::Io(err.to_string())
    }
}

/// Normalize a logical absolute path; reject escapes above `/`.
fn normalize_logical(path: &str) -> Result<String, FsError> {
    if !path.starts_with('/') {
        return Err(FsError::InvalidPath);
    }
    let mut stack: Vec<&str> = Vec::new();
    for part in path.split('/') {
        if part.is_empty() || part == "." {
            continue;
        }
        if part == ".." {
            if stack.pop().is_none() {
                return Err(FsError::Escape);
            }
            continue;
        }
        if part.contains('\0') {
            return Err(FsError::InvalidPath);
        }
        stack.push(part);
    }
    if stack.is_empty() {
        Ok("/".to_string())
    } else {
        Ok(format!("/{}", stack.join("/")))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn staging() -> (PathBuf, GuestFs) {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let root = std::env::temp_dir().join(format!("ryoku-console-fs-{nanos}"));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(root.join("home/ryoku")).unwrap();
        fs::create_dir_all(root.join("etc")).unwrap();
        fs::create_dir_all(root.join("bin")).unwrap();
        fs::write(root.join("etc/ryoku-release"), b"ryoku-minimal 0.1.0\n").unwrap();
        fs::write(root.join("home/ryoku/readme.txt"), b"hello minimal\n").unwrap();
        fs::write(root.join("bin/ryoku-console"), b"fake").unwrap();
        let gfs = GuestFs::new(root.clone());
        (root, gfs)
    }

    #[test]
    fn pwd_defaults_to_home_ryoku() {
        let (root, gfs) = staging();
        assert_eq!(gfs.pwd(), "/home/ryoku\n");
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn ls_and_cat_confined() {
        let (root, gfs) = staging();
        let listing = gfs.ls(None).unwrap();
        assert!(listing.contains("readme.txt"));
        assert_eq!(gfs.cat("readme.txt").unwrap(), "hello minimal\n");
        assert_eq!(
            gfs.cat("/etc/ryoku-release").unwrap(),
            "ryoku-minimal 0.1.0\n"
        );
        // From /home/ryoku, ../../etc stays under guest `/`.
        assert_eq!(
            gfs.cat("../../etc/ryoku-release").unwrap(),
            "ryoku-minimal 0.1.0\n"
        );
        // Escaping above guest `/` is rejected.
        assert!(matches!(
            gfs.resolve("/../../etc/passwd"),
            Err(FsError::Escape)
        ));
        assert!(matches!(gfs.resolve("../../.."), Err(FsError::Escape)));
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn ls_bin_and_reject_dir_as_cat() {
        let (root, gfs) = staging();
        let listing = gfs.ls(Some("/bin")).unwrap();
        assert!(listing.contains("ryoku-console"));
        assert!(matches!(gfs.cat("/home/ryoku"), Err(FsError::IsDir)));
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn cat_rejects_oversized() {
        let (root, gfs) = staging();
        let big = root.join("home/ryoku/big.bin");
        fs::write(&big, vec![b'x'; MAX_CAT_BYTES + 1]).unwrap();
        assert!(matches!(gfs.cat("big.bin"), Err(FsError::TooLarge { .. })));
        let _ = fs::remove_dir_all(root);
    }
}
