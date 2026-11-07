//! Optional experimental filesystem view for Ryoku Minimal (Mission 012 hardening).
//!
//! Confines `pwd` / `ls` / `cat` to a staged root. No writes, no mounts, no
//! persistence. **All symlinks are rejected** (this Minimal version does not
//! follow links). Host sessions require an explicit validated
//! `RYOKU_CONSOLE_ROOT`; guest Minimal uses `/` via that same env from PID 1.
//!
//! # Residual TOCTOU
//!
//! After `symlink_metadata` / component walk rejects links, a concurrent
//! replacement of a path component with a symlink before `File::open` /
//! `read_dir` could race. This Minimal console does not use `O_NOFOLLOW` (no
//! extra libc dep) and documents that residual window. Lab guests are
//! single-user / non-adversarial; do not treat this as a hardened multi-tenant
//! sandbox.

#![forbid(unsafe_code)]

use std::fs;
use std::io::{self, Read};
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
    Symlink,
    TooLarge {
        size: u64,
    },
    TooManyEntries {
        count: usize,
    },
    Io(String),
    InvalidPath,
    /// Host REPL: experimental FS disabled until `RYOKU_CONSOLE_ROOT` is set.
    RootRequired,
}

impl std::fmt::Display for FsError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Escape => write!(f, "path escapes experimental root"),
            Self::NotFound => write!(f, "no such file or directory"),
            Self::NotDir => write!(f, "not a directory"),
            Self::IsDir => write!(f, "is a directory"),
            Self::Symlink => write!(f, "symlinks rejected in experimental FS"),
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
            Self::RootRequired => write!(
                f,
                "experimental FS requires RYOKU_CONSOLE_ROOT (host); guest sets it to /"
            ),
        }
    }
}

impl std::error::Error for FsError {}

/// Confined guest/host experimental filesystem cursor.
#[derive(Debug, Clone)]
pub struct GuestFs {
    /// Absolute host path that acts as guest `/` (no symlink root).
    root: PathBuf,
    /// Logical cwd inside the guest (`/`-prefixed, no `..`).
    cwd: String,
}

impl GuestFs {
    /// Create a view rooted at `root` with logical cwd `/home/ryoku` when that
    /// directory exists under root, otherwise `/`.
    ///
    /// Prefer [`Self::validated_root`] for host/`RYOKU_CONSOLE_ROOT` paths.
    #[must_use]
    pub fn new(root: PathBuf) -> Self {
        let mut gfs = Self {
            root,
            cwd: "/".to_string(),
        };
        // Existence check uses symlink_metadata via ensure on join — here only
        // lexical presence for cwd default (validated_root already checked root).
        if path_is_plain_dir(&gfs.root.join("home/ryoku")) {
            gfs.cwd = "/home/ryoku".to_string();
        }
        gfs
    }

    /// Validate a host or guest root: must exist, be a plain directory (not a
    /// symlink), and be absolute after canonicalize.
    pub fn validated_root(root: PathBuf) -> Result<Self, FsError> {
        if root.as_os_str().is_empty() {
            return Err(FsError::InvalidPath);
        }
        let meta = fs::symlink_metadata(&root).map_err(map_io)?;
        if meta.file_type().is_symlink() {
            return Err(FsError::Symlink);
        }
        if !meta.is_dir() {
            return Err(FsError::NotDir);
        }
        let canon = root.canonicalize().map_err(map_io)?;
        // Re-check after canonicalize (parent resolution).
        let meta2 = fs::symlink_metadata(&canon).map_err(map_io)?;
        if meta2.file_type().is_symlink() {
            return Err(FsError::Symlink);
        }
        if !meta2.is_dir() {
            return Err(FsError::NotDir);
        }
        Ok(Self::new(canon))
    }

    /// Guest Minimal root `/` (initramfs). Caller should only use when PID 1
    /// exported `RYOKU_CONSOLE_ROOT=/` (or tests that intentionally model guest).
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

    /// Resolve a user path to a host path under `root` (lexical, no escape).
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

    /// Lexical resolve + physical walk: reject any symlink component.
    fn resolve_physical(&self, user_path: &str) -> Result<(String, PathBuf), FsError> {
        let (logical, host) = self.resolve(user_path)?;
        ensure_no_symlinks_under_root(&self.root, &host)?;
        Ok((logical, host))
    }

    /// List a directory (default: cwd). Names only, one per line, sorted.
    /// Symlink directory targets are rejected; symlink *entries* are omitted.
    pub fn ls(&self, path: Option<&str>) -> Result<String, FsError> {
        let user = path.unwrap_or(".");
        let (_logical, host) = self.resolve_physical(user)?;
        let meta = fs::symlink_metadata(&host).map_err(map_io)?;
        if meta.file_type().is_symlink() {
            return Err(FsError::Symlink);
        }
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
            if !s.is_ascii() {
                continue;
            }
            // Reject/skip symlinks in listings — never follow.
            let ft = ent.file_type().map_err(map_io)?;
            if ft.is_symlink() {
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

    /// Read a regular file with a hard read cap (`MAX_CAT_BYTES`). Symlinks rejected.
    pub fn cat(&self, path: &str) -> Result<String, FsError> {
        let (_logical, host) = self.resolve_physical(path)?;
        let meta = fs::symlink_metadata(&host).map_err(map_io)?;
        if meta.file_type().is_symlink() {
            return Err(FsError::Symlink);
        }
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
        let buf = read_capped(&host)?;
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

/// Read at most [`MAX_CAT_BYTES`] bytes; one extra byte detects overflow.
fn read_capped(path: &Path) -> Result<Vec<u8>, FsError> {
    let mut f = fs::File::open(path).map_err(map_io)?;
    let mut buf = vec![0u8; MAX_CAT_BYTES + 1];
    let mut total = 0usize;
    loop {
        if total == buf.len() {
            break;
        }
        match f.read(&mut buf[total..]) {
            Ok(0) => break,
            Ok(n) => total += n,
            Err(err) if err.kind() == io::ErrorKind::Interrupted => continue,
            Err(err) => return Err(map_io(err)),
        }
    }
    if total > MAX_CAT_BYTES {
        return Err(FsError::TooLarge {
            size: (MAX_CAT_BYTES as u64).saturating_add(1),
        });
    }
    buf.truncate(total);
    Ok(buf)
}

fn path_is_plain_dir(path: &Path) -> bool {
    match fs::symlink_metadata(path) {
        Ok(m) => !m.file_type().is_symlink() && m.is_dir(),
        Err(_) => false,
    }
}

/// Walk from `root` to `target`, rejecting any symlink component.
///
/// `target` must be `root` or a descendant via normal components only.
fn ensure_no_symlinks_under_root(root: &Path, target: &Path) -> Result<(), FsError> {
    let rel = if target == root {
        Path::new("")
    } else {
        target.strip_prefix(root).map_err(|_| FsError::Escape)?
    };
    let mut cur = root.to_path_buf();
    // Root itself must not be a symlink.
    let root_meta = fs::symlink_metadata(&cur).map_err(map_io)?;
    if root_meta.file_type().is_symlink() {
        return Err(FsError::Symlink);
    }
    for c in rel.components() {
        match c {
            Component::Normal(name) => {
                cur.push(name);
                let meta = fs::symlink_metadata(&cur).map_err(map_io)?;
                if meta.file_type().is_symlink() {
                    return Err(FsError::Symlink);
                }
            }
            Component::CurDir => {}
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => {
                return Err(FsError::Escape);
            }
        }
    }
    Ok(())
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
    use std::os::unix::fs::symlink;
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
        let gfs = GuestFs::validated_root(root.clone()).unwrap();
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
        assert_eq!(
            gfs.cat("../../etc/ryoku-release").unwrap(),
            "ryoku-minimal 0.1.0\n"
        );
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
    fn cat_rejects_oversized_and_accepts_exact_limit() {
        let (root, gfs) = staging();
        let exact = root.join("home/ryoku/exact.bin");
        fs::write(&exact, vec![b'e'; MAX_CAT_BYTES]).unwrap();
        let out = gfs.cat("exact.bin").unwrap();
        assert_eq!(out.len(), MAX_CAT_BYTES + 1); // payload + trailing \n
        assert!(out.as_bytes()[..MAX_CAT_BYTES].iter().all(|&b| b == b'e'));

        let big = root.join("home/ryoku/big.bin");
        fs::write(&big, vec![b'x'; MAX_CAT_BYTES + 1]).unwrap();
        assert!(matches!(gfs.cat("big.bin"), Err(FsError::TooLarge { .. })));
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn cat_rejects_nul_and_invalid_utf8() {
        let (root, gfs) = staging();
        fs::write(root.join("home/ryoku/nul.txt"), b"a\0b").unwrap();
        assert!(matches!(gfs.cat("nul.txt"), Err(FsError::Io(_))));
        fs::write(root.join("home/ryoku/bad.txt"), b"ok\xffno").unwrap();
        assert!(matches!(gfs.cat("bad.txt"), Err(FsError::Io(_))));
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn symlinks_are_rejected_without_reading_external() {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let base = std::env::temp_dir().join(format!("ryoku-console-sym-{nanos}"));
        let _ = fs::remove_dir_all(&base);
        let root = base.join("root");
        let outside = base.join("outside");
        fs::create_dir_all(root.join("home/ryoku")).unwrap();
        fs::create_dir_all(&outside).unwrap();
        // Fake "external" secret — must never be returned by cat.
        let secret = outside.join("secret.txt");
        fs::write(&secret, b"EXTERNAL_SECRET_SHOULD_NOT_LEAK\n").unwrap();
        symlink(&secret, root.join("home/ryoku/leak.txt")).unwrap();
        symlink(&outside, root.join("home/ryoku/ext_dir")).unwrap();

        let gfs = GuestFs::validated_root(root.clone()).unwrap();
        assert!(
            matches!(gfs.cat("leak.txt"), Err(FsError::Symlink)),
            "file symlink must be rejected"
        );
        assert!(
            matches!(gfs.cat("/home/ryoku/leak.txt"), Err(FsError::Symlink)),
            "absolute symlink path rejected"
        );
        assert!(
            matches!(gfs.ls(Some("ext_dir")), Err(FsError::Symlink)),
            "dir symlink must be rejected"
        );
        // Listing cwd must omit the symlink entry (not follow / leak).
        let listing = gfs.ls(None).unwrap();
        assert!(
            !listing.contains("leak.txt"),
            "symlink names omitted from ls"
        );
        assert!(!listing.contains("EXTERNAL_SECRET"));
        let _ = fs::remove_dir_all(&base);
    }

    #[test]
    fn validated_root_rejects_symlink_root() {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let base = std::env::temp_dir().join(format!("ryoku-console-rootlink-{nanos}"));
        let _ = fs::remove_dir_all(&base);
        let real = base.join("real");
        let link = base.join("link");
        fs::create_dir_all(&real).unwrap();
        symlink(&real, &link).unwrap();
        assert!(matches!(
            GuestFs::validated_root(link),
            Err(FsError::Symlink)
        ));
        let _ = fs::remove_dir_all(&base);
    }

    #[test]
    fn read_capped_detects_overflow_byte() {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("ryoku-console-cap-{nanos}"));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("x");
        fs::write(&path, vec![b'z'; MAX_CAT_BYTES + 3]).unwrap();
        // Bypass metadata fast-path by calling read_capped directly.
        assert!(matches!(read_capped(&path), Err(FsError::TooLarge { .. })));
        let path2 = dir.join("ok");
        fs::write(&path2, vec![b'z'; MAX_CAT_BYTES]).unwrap();
        assert_eq!(read_capped(&path2).unwrap().len(), MAX_CAT_BYTES);
        let _ = fs::remove_dir_all(&dir);
    }
}
