//! Minimal newc cpio helpers for Boot Seed structure tests (Mission 008).
//!
//! Packs only files staged under a disposable directory — never host system paths.
//! The production packer remains `tests/qemu/scripts/build-boot-seed-initramfs.sh`.

use std::fs;
use std::io::{self, Write};
use std::path::{Component, Path, PathBuf};

/// Relative archive member that must exist for a boot-seed initramfs.
pub const REQUIRED_INIT_MEMBER: &str = "./init";

/// Reject absolute paths, `..`, and empty names for staged members.
pub fn assert_safe_member_name(name: &str) -> Result<(), String> {
    let n = name.trim();
    if n.is_empty() {
        return Err("empty member name".into());
    }
    if n.starts_with('/') || Path::new(n).is_absolute() {
        return Err(format!("absolute member path forbidden: {n}"));
    }
    for c in Path::new(n).components() {
        match c {
            Component::Normal(_) | Component::CurDir => {}
            Component::ParentDir => {
                return Err(format!("parent escape in member path: {n}"));
            }
            Component::RootDir | Component::Prefix(_) => {
                return Err(format!("absolute/prefix member path forbidden: {n}"));
            }
        }
    }
    if n.contains('\0') {
        return Err("NUL in member name".into());
    }
    Ok(())
}

/// True when a gzip'd or raw newc listing contains `./init` (or `init`).
#[must_use]
pub fn listing_has_init(listing: &str) -> bool {
    listing.lines().any(|line| {
        let t = line.trim();
        t == "./init" || t == "init" || t.ends_with("/init") && !t.contains("..")
    })
}

/// Write a single-file newc archive (uncompressed) with member `./init`.
pub fn write_newc_single_init(init_bytes: &[u8], out: &mut dyn Write) -> io::Result<()> {
    write_newc_file(out, "./init", 0o755, init_bytes)?;
    write_newc_trailer(out)?;
    Ok(())
}

fn write_newc_file(out: &mut dyn Write, name: &str, mode: u32, data: &[u8]) -> io::Result<()> {
    assert_safe_member_name(name).map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))?;
    // newc header: 110 ASCII hex bytes + name + NUL, then pad to 4, then data, pad to 4.
    let name_bytes = name.as_bytes();
    let namesize = name_bytes.len() + 1; // include NUL
    let mut hdr = Vec::with_capacity(110);
    // newc: magic(6) + 13×8 hex fields (ino…check) = 110 bytes.
    write!(
        &mut hdr,
        "070701\
{:08x}{:08x}{:08x}{:08x}{:08x}{:08x}{:08x}\
{:08x}{:08x}{:08x}{:08x}{:08x}00000000",
        1u32,             // ino
        mode | 0o100_000, // mode = S_IFREG | perms
        0u32,             // uid
        0u32,             // gid
        1u32,             // nlink
        0u32,             // mtime
        data.len() as u32,
        0u32, // major
        0u32, // minor
        0u32, // rmajor
        0u32, // rminor
        namesize as u32,
    )?;
    debug_assert_eq!(hdr.len(), 110);
    out.write_all(&hdr)?;
    out.write_all(name_bytes)?;
    out.write_all(&[0])?;
    pad4(out, 110 + namesize)?;
    out.write_all(data)?;
    pad4(out, data.len())?;
    Ok(())
}

fn write_newc_trailer(out: &mut dyn Write) -> io::Result<()> {
    // TRAILER!!! with zero sizes.
    let name = b"TRAILER!!!";
    let namesize = name.len() + 1;
    let mut hdr = Vec::with_capacity(110);
    write!(
        &mut hdr,
        "070701\
00000000\
00000000\
00000000\
00000000\
00000001\
00000000\
00000000\
00000000\
00000000\
00000000\
00000000\
{:08x}\
00000000",
        namesize as u32
    )?;
    debug_assert_eq!(hdr.len(), 110);
    out.write_all(&hdr)?;
    out.write_all(name)?;
    out.write_all(&[0])?;
    pad4(out, 110 + namesize)?;
    Ok(())
}

fn pad4(out: &mut dyn Write, used: usize) -> io::Result<()> {
    let rem = used % 4;
    if rem != 0 {
        out.write_all(&[0u8; 3][..(4 - rem)])?;
    }
    Ok(())
}

/// Extract printable member names from an uncompressed newc stream (best-effort).
pub fn list_newc_members(archive: &[u8]) -> Result<Vec<String>, String> {
    let mut out = Vec::new();
    let mut i = 0;
    while i + 110 <= archive.len() {
        if &archive[i..i + 6] != b"070701" {
            return Err(format!("bad magic at offset {i}"));
        }
        let namesize = parse_hex_u32(&archive[i + 94..i + 102])?;
        let filesize = parse_hex_u32(&archive[i + 54..i + 62])?;
        let name_start = i + 110;
        let name_end = name_start + namesize as usize;
        if name_end > archive.len() {
            return Err("truncated name".into());
        }
        let raw = &archive[name_start..name_end];
        let name = std::str::from_utf8(&raw[..raw.len().saturating_sub(1)])
            .map_err(|_| "non-utf8 name".to_string())?
            .to_string();
        if name == "TRAILER!!!" {
            break;
        }
        out.push(name);
        let after_name = align4(name_end);
        let data_end = after_name + filesize as usize;
        if data_end > archive.len() {
            return Err("truncated data".into());
        }
        i = align4(data_end);
    }
    Ok(out)
}

fn parse_hex_u32(slice: &[u8]) -> Result<u32, String> {
    let s = std::str::from_utf8(slice).map_err(|_| "hex utf8".to_string())?;
    u32::from_str_radix(s, 16).map_err(|_| format!("bad hex `{s}`"))
}

fn align4(n: usize) -> usize {
    (n + 3) & !3
}

/// Stage `init_bytes` as `./init` under `staging_root` and return the init path.
/// Refuses if `staging_root` would require writing outside itself.
pub fn stage_init_only(staging_root: &Path, init_bytes: &[u8]) -> Result<PathBuf, String> {
    if staging_root.is_absolute() {
        // Absolute temp dirs are OK (mktemp); still never copy from host system roots.
    }
    fs::create_dir_all(staging_root).map_err(|e| e.to_string())?;
    let init_path = staging_root.join("init");
    // Path safety: resolved init must stay under staging_root.
    let staged = init_path
        .canonicalize()
        .or_else(|_| {
            // File may not exist yet — validate parent.
            fs::create_dir_all(staging_root)?;
            Ok::<_, io::Error>(staging_root.join("init"))
        })
        .map_err(|e| e.to_string())?;
    let root_canon = staging_root.canonicalize().map_err(|e| e.to_string())?;
    if let Ok(c) = staged.canonicalize() {
        if !c.starts_with(&root_canon) {
            return Err("init path escaped staging root".into());
        }
    } else if !staged.starts_with(staging_root) {
        return Err("init path escaped staging root".into());
    }
    fs::write(&init_path, init_bytes).map_err(|e| e.to_string())?;
    Ok(init_path)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;

    #[test]
    fn member_path_safety() {
        assert!(assert_safe_member_name("./init").is_ok());
        assert!(assert_safe_member_name("init").is_ok());
        assert!(assert_safe_member_name("/etc/passwd").is_err());
        assert!(assert_safe_member_name("../etc/passwd").is_err());
        assert!(assert_safe_member_name("").is_err());
    }

    #[test]
    fn newc_roundtrip_lists_init() {
        let mut buf = Vec::new();
        write_newc_single_init(b"#!/ryoku-init\n", &mut buf).unwrap();
        let members = list_newc_members(&buf).unwrap();
        assert_eq!(members, vec!["./init".to_string()]);
        let listing = members.join("\n");
        assert!(listing_has_init(&listing));
    }

    #[test]
    fn stage_init_stays_in_temp() {
        let dir = env::temp_dir().join(format!("ryoku-initramfs-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let path = stage_init_only(&dir, b"seed").unwrap();
        assert!(path.ends_with("init"));
        assert_eq!(fs::read(&path).unwrap(), b"seed");
        let _ = fs::remove_dir_all(&dir);
    }
}
