//! Minimal newc cpio helpers for Boot Seed / Ryoku Minimal (Mission 008.5 / 012).
//!
//! Packs only staged content — never host system paths or real `/dev` nodes from the host.
//! Char devices are encoded as **archive metadata** (newc headers), not created with mknod/sudo.
//!
//! - [`boot_seed_members`] — original T3 (init + `/dev/console` only) — **unchanged**.
//! - [`ryoku_minimal_members`] — experimental Minimal FS + `ryoku-console` (interactive).

use std::fs;
use std::io::{self, Write};
use std::path::{Component, Path, PathBuf};

/// Relative archive member that must exist for a boot-seed initramfs.
pub const REQUIRED_INIT_MEMBER: &str = "./init";
/// Console device member (char 5:1).
pub const REQUIRED_CONSOLE_MEMBER: &str = "./dev/console";
/// Interactive console binary (Ryoku Minimal only — **not** in original T3).
pub const REQUIRED_CONSOLE_BIN_MEMBER: &str = "./bin/ryoku-console";
/// Release identity file (Ryoku Minimal).
pub const REQUIRED_RELEASE_MEMBER: &str = "./etc/ryoku-release";
/// Default home directory member (Ryoku Minimal).
pub const REQUIRED_HOME_MEMBER: &str = "./home/ryoku";

/// Default contents of `./etc/ryoku-release` in Minimal initramfs.
pub const RYOKU_RELEASE_TEXT: &str = "ryoku-minimal 0.1.0 (Mission 012)\n";

/// Graphics package release text (Mission 014.1) — separate from serial Minimal package.
pub const RYOKU_GRAPHICS_RELEASE_TEXT: &str =
    "ryoku-minimal 0.1.0 (Mission 014.1 graphics preview + virt DRM modules)\n";

/// Shell package release text (Mission 015) — separate from First Pixels package.
pub const RYOKU_SHELL_RELEASE_TEXT: &str =
    "ryoku-minimal 0.1.0 (Mission 015.1 shell + guest evdev + virt DRM/input modules)\n";

/// Graphics demo binary member (Mission 014 package only).
pub const REQUIRED_GRAPHICS_DEMO_MEMBER: &str = "./bin/ryoku-graphics-demo";

/// Shell preview binary member (Mission 015 package only — not alongside graphics-demo).
pub const REQUIRED_SHELL_PREVIEW_MEMBER: &str = "./bin/ryoku-shell-preview";

/// Guest modules root prefix inside graphics cpio (Mission 014.1).
pub const GRAPHICS_MODULES_ROOT_MEMBER: &str = "./lib/modules/6.12.114-0-virt";

/// Allowlisted DRM module archive members (Mission 014.1) — relative to archive root.
pub const REQUIRED_GRAPHICS_MODULE_MEMBERS: &[&str] = &[
    "./lib/modules/6.12.114-0-virt/kernel/drivers/virtio/virtio_dma_buf.ko",
    "./lib/modules/6.12.114-0-virt/kernel/drivers/video/fbdev/core/syscopyarea.ko",
    "./lib/modules/6.12.114-0-virt/kernel/drivers/video/fbdev/core/sysfillrect.ko",
    "./lib/modules/6.12.114-0-virt/kernel/drivers/video/fbdev/core/sysimgblt.ko",
    "./lib/modules/6.12.114-0-virt/kernel/drivers/video/fbdev/core/fb_sys_fops.ko",
    "./lib/modules/6.12.114-0-virt/kernel/drivers/gpu/drm/drm_panel_orientation_quirks.ko",
    "./lib/modules/6.12.114-0-virt/kernel/drivers/i2c/i2c-core.ko",
    "./lib/modules/6.12.114-0-virt/kernel/drivers/gpu/drm/drm.ko",
    "./lib/modules/6.12.114-0-virt/kernel/drivers/video/fbdev/core/fb.ko",
    "./lib/modules/6.12.114-0-virt/kernel/drivers/gpu/drm/drm_kms_helper.ko",
    "./lib/modules/6.12.114-0-virt/kernel/drivers/gpu/drm/drm_shmem_helper.ko",
    "./lib/modules/6.12.114-0-virt/kernel/drivers/gpu/drm/virtio/virtio-gpu.ko",
    // Mission 015.1 — guest input (shell + graphics packages share the staged tree).
    "./lib/modules/6.12.114-0-virt/kernel/drivers/input/evdev.ko",
    "./lib/modules/6.12.114-0-virt/kernel/drivers/virtio/virtio_input.ko",
];

const S_IFREG: u32 = 0o100_000;
const S_IFDIR: u32 = 0o040_000;
const S_IFCHR: u32 = 0o020_000;

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

/// True when a listing contains `./init` (or `init`).
#[must_use]
pub fn listing_has_init(listing: &str) -> bool {
    listing.lines().any(|line| {
        let t = line.trim();
        t == "./init" || t == "init" || (t.ends_with("/init") && !t.contains(".."))
    })
}

/// True when listing contains `./dev/console`.
#[must_use]
pub fn listing_has_console(listing: &str) -> bool {
    listing.lines().any(|line| {
        let t = line.trim();
        t == "./dev/console" || t == "dev/console"
    })
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NewcMember {
    pub name: String,
    pub mode: u32,
    pub rmajor: u32,
    pub rminor: u32,
    pub data: Vec<u8>,
}

impl NewcMember {
    #[must_use]
    pub fn file(name: &str, mode: u32, data: Vec<u8>) -> Self {
        Self {
            name: name.to_string(),
            mode: S_IFREG | (mode & 0o7777),
            rmajor: 0,
            rminor: 0,
            data,
        }
    }

    #[must_use]
    pub fn dir(name: &str, mode: u32) -> Self {
        Self {
            name: name.to_string(),
            mode: S_IFDIR | (mode & 0o7777),
            rmajor: 0,
            rminor: 0,
            data: Vec::new(),
        }
    }

    #[must_use]
    pub fn chr(name: &str, mode: u32, major: u32, minor: u32) -> Self {
        Self {
            name: name.to_string(),
            mode: S_IFCHR | (mode & 0o7777),
            rmajor: major,
            rminor: minor,
            data: Vec::new(),
        }
    }

    #[must_use]
    pub fn is_chr_console_5_1(&self) -> bool {
        (self.mode & S_IFCHR) == S_IFCHR
            && self.rmajor == 5
            && self.rminor == 1
            && (self.name == "./dev/console" || self.name == "dev/console")
    }

    #[must_use]
    pub fn is_executable_init(&self) -> bool {
        (self.mode & S_IFREG) == S_IFREG
            && (self.mode & 0o111) != 0
            && (self.name == "./init" || self.name == "init")
    }
}

/// Canonical Boot Seed archive members: dirs + `/dev/console` (5,1) + `/init`.
///
/// **T3 contract:** no `./bin/ryoku-console` — PID 1 must stay idle after READY.
#[must_use]
pub fn boot_seed_members(init_bytes: &[u8]) -> Vec<NewcMember> {
    vec![
        NewcMember::dir("./dev", 0o755),
        NewcMember::chr("./dev/console", 0o600, 5, 1),
        NewcMember::dir("./proc", 0o755),
        NewcMember::dir("./sys", 0o755),
        NewcMember::dir("./tmp", 0o755),
        NewcMember::file("./init", 0o755, init_bytes.to_vec()),
    ]
}

/// Ryoku Minimal experimental initramfs members (Mission 012).
///
/// Layout: `/init`, `/bin/ryoku-console`, `/dev/console`, `/etc/ryoku-release`,
/// `/home/ryoku/`, plus standard empty dirs.
#[must_use]
pub fn ryoku_minimal_members(
    init_bytes: &[u8],
    console_bytes: &[u8],
    release_text: &str,
) -> Vec<NewcMember> {
    vec![
        NewcMember::dir("./dev", 0o755),
        NewcMember::chr("./dev/console", 0o600, 5, 1),
        NewcMember::dir("./bin", 0o755),
        NewcMember::dir("./etc", 0o755),
        NewcMember::dir("./home", 0o755),
        NewcMember::dir("./home/ryoku", 0o755),
        NewcMember::dir("./proc", 0o755),
        NewcMember::dir("./sys", 0o755),
        NewcMember::dir("./tmp", 0o755),
        NewcMember::file("./init", 0o755, init_bytes.to_vec()),
        NewcMember::file("./bin/ryoku-console", 0o755, console_bytes.to_vec()),
        NewcMember::file(
            "./etc/ryoku-release",
            0o644,
            release_text.as_bytes().to_vec(),
        ),
    ]
}

/// Write a boot-seed newc archive (uncompressed).
pub fn write_boot_seed_newc(init_bytes: &[u8], out: &mut dyn Write) -> io::Result<()> {
    write_newc_archive(&boot_seed_members(init_bytes), out)
}

/// Write a Ryoku Minimal newc archive (uncompressed).
pub fn write_ryoku_minimal_newc(
    init_bytes: &[u8],
    console_bytes: &[u8],
    release_text: &str,
    out: &mut dyn Write,
) -> io::Result<()> {
    write_newc_archive(
        &ryoku_minimal_members(init_bytes, console_bytes, release_text),
        out,
    )
}

/// Ryoku Minimal + graphics demo members (Mission 014). Does not replace T3/Minimal serial pack.
#[must_use]
pub fn ryoku_graphics_members(
    init_bytes: &[u8],
    console_bytes: &[u8],
    graphics_demo_bytes: &[u8],
    release_text: &str,
) -> Vec<NewcMember> {
    let mut members = ryoku_minimal_members(init_bytes, console_bytes, release_text);
    members.push(NewcMember::file(
        "./bin/ryoku-graphics-demo",
        0o755,
        graphics_demo_bytes.to_vec(),
    ));
    members
}

/// Ryoku Minimal + shell preview members (Mission 015). No graphics-demo (avoid dual FB).
#[must_use]
pub fn ryoku_shell_members(
    init_bytes: &[u8],
    console_bytes: &[u8],
    shell_preview_bytes: &[u8],
    release_text: &str,
) -> Vec<NewcMember> {
    let mut members = ryoku_minimal_members(init_bytes, console_bytes, release_text);
    members.push(NewcMember::file(
        "./bin/ryoku-shell-preview",
        0o755,
        shell_preview_bytes.to_vec(),
    ));
    members
}

/// Append allowlisted DRM `.ko` files + parent dirs from a staged modules tree.
///
/// `modules_root` is the host directory whose contents map to
/// `/lib/modules/6.12.114-0-virt/` (i.e. contains `kernel/.../*.ko`).
pub fn append_graphics_modules(
    members: &mut Vec<NewcMember>,
    modules_root: &Path,
) -> Result<(), String> {
    if !modules_root.is_dir() {
        return Err(format!(
            "graphics modules root missing or not a directory: {}",
            modules_root.display()
        ));
    }
    // Parent directory chain for the modules root.
    for dir in [
        "./lib",
        "./lib/modules",
        GRAPHICS_MODULES_ROOT_MEMBER,
        "./lib/modules/6.12.114-0-virt/kernel",
        "./lib/modules/6.12.114-0-virt/kernel/drivers",
        "./lib/modules/6.12.114-0-virt/kernel/drivers/virtio",
        "./lib/modules/6.12.114-0-virt/kernel/drivers/video",
        "./lib/modules/6.12.114-0-virt/kernel/drivers/video/fbdev",
        "./lib/modules/6.12.114-0-virt/kernel/drivers/video/fbdev/core",
        "./lib/modules/6.12.114-0-virt/kernel/drivers/gpu",
        "./lib/modules/6.12.114-0-virt/kernel/drivers/gpu/drm",
        "./lib/modules/6.12.114-0-virt/kernel/drivers/gpu/drm/virtio",
        "./lib/modules/6.12.114-0-virt/kernel/drivers/i2c",
        "./lib/modules/6.12.114-0-virt/kernel/drivers/input",
    ] {
        if !members.iter().any(|m| m.name == dir) {
            members.push(NewcMember::dir(dir, 0o755));
        }
    }

    for member in REQUIRED_GRAPHICS_MODULE_MEMBERS {
        let rel = member
            .strip_prefix("./lib/modules/6.12.114-0-virt/")
            .ok_or_else(|| format!("internal: bad module member {member}"))?;
        // Path safety: refuse `..` / absolute.
        assert_safe_member_name(member)?;
        let host = modules_root.join(rel);
        if !host.is_file() {
            return Err(format!(
                "missing allowlisted module at {} (expected for {member})",
                host.display()
            ));
        }
        // Refuse reading outside modules_root.
        let host_canon = host
            .canonicalize()
            .map_err(|e| format!("canon {rel}: {e}"))?;
        let root_canon = modules_root
            .canonicalize()
            .map_err(|e| format!("canon modules_root: {e}"))?;
        if !host_canon.starts_with(&root_canon) {
            return Err(format!("module path escaped modules_root: {rel}"));
        }
        let data = fs::read(&host_canon).map_err(|e| format!("read {rel}: {e}"))?;
        if data.is_empty() {
            return Err(format!("empty module file: {rel}"));
        }
        members.push(NewcMember::file(member, 0o644, data));
    }
    Ok(())
}

/// Write graphics-preview newc archive (uncompressed).
pub fn write_ryoku_graphics_newc(
    init_bytes: &[u8],
    console_bytes: &[u8],
    graphics_demo_bytes: &[u8],
    release_text: &str,
    out: &mut dyn Write,
) -> io::Result<()> {
    write_newc_archive(
        &ryoku_graphics_members(init_bytes, console_bytes, graphics_demo_bytes, release_text),
        out,
    )
}

/// Write graphics-preview newc including allowlisted DRM modules (Mission 014.1).
pub fn write_ryoku_graphics_newc_with_modules(
    init_bytes: &[u8],
    console_bytes: &[u8],
    graphics_demo_bytes: &[u8],
    release_text: &str,
    modules_root: &Path,
    out: &mut dyn Write,
) -> Result<(), String> {
    let mut members =
        ryoku_graphics_members(init_bytes, console_bytes, graphics_demo_bytes, release_text);
    append_graphics_modules(&mut members, modules_root)?;
    write_newc_archive(&members, out).map_err(|e| e.to_string())
}

/// Write an arbitrary newc archive then TRAILER.
pub fn write_newc_archive(members: &[NewcMember], out: &mut dyn Write) -> io::Result<()> {
    for (i, m) in members.iter().enumerate() {
        write_newc_member(out, m, (i as u32).saturating_add(1))?;
    }
    write_newc_trailer(out)?;
    Ok(())
}

/// Write a single-file newc archive (uncompressed) with member `./init` (tests).
pub fn write_newc_single_init(init_bytes: &[u8], out: &mut dyn Write) -> io::Result<()> {
    write_newc_archive(
        &[NewcMember::file("./init", 0o755, init_bytes.to_vec())],
        out,
    )
}

fn write_newc_member(out: &mut dyn Write, m: &NewcMember, ino: u32) -> io::Result<()> {
    assert_safe_member_name(&m.name).map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))?;
    let name_bytes = m.name.as_bytes();
    let namesize = name_bytes.len() + 1;
    let filesize = if (m.mode & S_IFCHR) == S_IFCHR || (m.mode & S_IFDIR) == S_IFDIR {
        0u32
    } else {
        m.data.len() as u32
    };
    let mut hdr = Vec::with_capacity(110);
    write!(
        &mut hdr,
        "070701\
{:08x}{:08x}{:08x}{:08x}{:08x}{:08x}{:08x}\
{:08x}{:08x}{:08x}{:08x}{:08x}00000000",
        ino,
        m.mode,
        0u32, // uid
        0u32, // gid
        1u32, // nlink
        0u32, // mtime (controlled; packer may ignore host clocks)
        filesize,
        0u32, // major
        0u32, // minor
        m.rmajor,
        m.rminor,
        namesize as u32,
    )?;
    debug_assert_eq!(hdr.len(), 110);
    out.write_all(&hdr)?;
    out.write_all(name_bytes)?;
    out.write_all(&[0])?;
    pad4(out, 110 + namesize)?;
    if filesize > 0 {
        out.write_all(&m.data)?;
        pad4(out, m.data.len())?;
    }
    Ok(())
}

fn write_newc_trailer(out: &mut dyn Write) -> io::Result<()> {
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

/// Parsed newc entry (structure / metadata inspection).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedNewc {
    pub name: String,
    pub mode: u32,
    pub filesize: u32,
    pub rmajor: u32,
    pub rminor: u32,
}

/// Parse uncompressed newc members with metadata.
pub fn parse_newc_members(archive: &[u8]) -> Result<Vec<ParsedNewc>, String> {
    let mut out = Vec::new();
    let mut i = 0;
    while i + 110 <= archive.len() {
        if &archive[i..i + 6] != b"070701" {
            return Err(format!("bad magic at offset {i}"));
        }
        let mode = parse_hex_u32(&archive[i + 14..i + 22])?;
        let filesize = parse_hex_u32(&archive[i + 54..i + 62])?;
        let rmajor = parse_hex_u32(&archive[i + 78..i + 86])?;
        let rminor = parse_hex_u32(&archive[i + 86..i + 94])?;
        let namesize = parse_hex_u32(&archive[i + 94..i + 102])?;
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
        out.push(ParsedNewc {
            name,
            mode,
            filesize,
            rmajor,
            rminor,
        });
        let after_name = align4(name_end);
        let data_end = after_name + filesize as usize;
        if data_end > archive.len() {
            return Err("truncated data".into());
        }
        i = align4(data_end);
    }
    Ok(out)
}

/// Extract printable member names from an uncompressed newc stream.
pub fn list_newc_members(archive: &[u8]) -> Result<Vec<String>, String> {
    Ok(parse_newc_members(archive)?
        .into_iter()
        .map(|m| m.name)
        .collect())
}

fn validate_common_init_and_console(members: &[ParsedNewc]) -> Result<(), String> {
    let names: Vec<_> = members.iter().map(|m| m.name.as_str()).collect();
    for n in &names {
        assert_safe_member_name(n)?;
        if *n == "." || n.starts_with("./..") {
            return Err(format!("unexpected member `{n}`"));
        }
    }
    let init = members
        .iter()
        .find(|m| m.name == "./init" || m.name == "init")
        .ok_or_else(|| "missing ./init".to_string())?;
    if (init.mode & S_IFREG) != S_IFREG {
        return Err("init is not a regular file".into());
    }
    if (init.mode & 0o111) == 0 {
        return Err("init is not executable".into());
    }
    if init.filesize == 0 {
        return Err("init is empty".into());
    }
    let console = members
        .iter()
        .find(|m| m.name == "./dev/console" || m.name == "dev/console")
        .ok_or_else(|| "missing ./dev/console".to_string())?;
    if (console.mode & S_IFCHR) != S_IFCHR {
        return Err(format!(
            "./dev/console is not a char device (mode={:o})",
            console.mode
        ));
    }
    if console.rmajor != 5 || console.rminor != 1 {
        return Err(format!(
            "./dev/console must be char 5:1 (got {}:{})",
            console.rmajor, console.rminor
        ));
    }
    if console.filesize != 0 {
        return Err("char device must have filesize 0".into());
    }
    Ok(())
}

/// Validate a boot-seed archive has executable `./init` and `./dev/console` char 5:1.
pub fn validate_boot_seed_cpio(archive: &[u8]) -> Result<(), String> {
    let members = parse_newc_members(archive)?;
    validate_common_init_and_console(&members)?;
    // Original T3 must NOT ship the interactive console binary.
    if members
        .iter()
        .any(|m| m.name == "./bin/ryoku-console" || m.name == "bin/ryoku-console")
    {
        return Err("boot-seed archive must not contain ./bin/ryoku-console (use Minimal)".into());
    }
    Ok(())
}

/// Validate Ryoku Minimal archive: boot-seed basics + console bin + release + home.
pub fn validate_ryoku_minimal_cpio(archive: &[u8]) -> Result<(), String> {
    let members = parse_newc_members(archive)?;
    validate_common_init_and_console(&members)?;
    let console_bin = members
        .iter()
        .find(|m| m.name == "./bin/ryoku-console" || m.name == "bin/ryoku-console")
        .ok_or_else(|| "missing ./bin/ryoku-console".to_string())?;
    if (console_bin.mode & S_IFREG) != S_IFREG {
        return Err("ryoku-console is not a regular file".into());
    }
    if (console_bin.mode & 0o111) == 0 {
        return Err("ryoku-console is not executable".into());
    }
    if console_bin.filesize == 0 {
        return Err("ryoku-console is empty".into());
    }
    let release = members
        .iter()
        .find(|m| m.name == "./etc/ryoku-release" || m.name == "etc/ryoku-release")
        .ok_or_else(|| "missing ./etc/ryoku-release".to_string())?;
    if (release.mode & S_IFREG) != S_IFREG {
        return Err("ryoku-release is not a regular file".into());
    }
    if release.filesize == 0 {
        return Err("ryoku-release is empty".into());
    }
    let home = members
        .iter()
        .find(|m| m.name == "./home/ryoku" || m.name == "home/ryoku")
        .ok_or_else(|| "missing ./home/ryoku".to_string())?;
    if (home.mode & S_IFDIR) != S_IFDIR {
        return Err("./home/ryoku is not a directory".into());
    }
    Ok(())
}

fn parse_hex_u32(slice: &[u8]) -> Result<u32, String> {
    let s = std::str::from_utf8(slice).map_err(|_| "hex utf8".to_string())?;
    u32::from_str_radix(s, 16).map_err(|_| format!("bad hex `{s}`"))
}

fn align4(n: usize) -> usize {
    (n + 3) & !3
}

/// Stage `init_bytes` as `./init` under `staging_root` and return the init path.
pub fn stage_init_only(staging_root: &Path, init_bytes: &[u8]) -> Result<PathBuf, String> {
    fs::create_dir_all(staging_root).map_err(|e| e.to_string())?;
    let init_path = staging_root.join("init");
    let staged = init_path
        .canonicalize()
        .or_else(|_| {
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

/// Pack boot-seed initramfs (uncompressed newc bytes) from an init binary path.
/// Refuses host-absolute escapes; does not read `/dev` from the host.
pub fn pack_boot_seed_from_init_path(init_path: &Path) -> Result<Vec<u8>, String> {
    let data = fs::read(init_path).map_err(|e| format!("read init: {e}"))?;
    if data.is_empty() {
        return Err("init binary empty".into());
    }
    let mut out = Vec::new();
    write_boot_seed_newc(&data, &mut out).map_err(|e| e.to_string())?;
    validate_boot_seed_cpio(&out)?;
    Ok(out)
}

/// Pack Ryoku Minimal initramfs from init + console static binaries.
pub fn pack_ryoku_minimal_from_paths(
    init_path: &Path,
    console_path: &Path,
    release_text: &str,
) -> Result<Vec<u8>, String> {
    let init = fs::read(init_path).map_err(|e| format!("read init: {e}"))?;
    let console = fs::read(console_path).map_err(|e| format!("read console: {e}"))?;
    if init.is_empty() {
        return Err("init binary empty".into());
    }
    if console.is_empty() {
        return Err("console binary empty".into());
    }
    let mut out = Vec::new();
    write_ryoku_minimal_newc(&init, &console, release_text, &mut out).map_err(|e| e.to_string())?;
    validate_ryoku_minimal_cpio(&out)?;
    Ok(out)
}

/// Validate graphics preview cpio (Minimal layout + graphics demo binary).
pub fn validate_ryoku_graphics_cpio(data: &[u8]) -> Result<(), String> {
    validate_ryoku_minimal_cpio(data)?;
    let members = list_newc_members(data)?;
    if !members.iter().any(|m| m == REQUIRED_GRAPHICS_DEMO_MEMBER) {
        return Err(format!("missing {REQUIRED_GRAPHICS_DEMO_MEMBER}"));
    }
    Ok(())
}

/// Validate graphics cpio that includes the allowlisted DRM module set (014.1).
pub fn validate_ryoku_graphics_cpio_with_modules(data: &[u8]) -> Result<(), String> {
    validate_ryoku_graphics_cpio(data)?;
    let members = list_newc_members(data)?;
    for req in REQUIRED_GRAPHICS_MODULE_MEMBERS {
        if !members.iter().any(|m| m == req) {
            return Err(format!("missing graphics module member {req}"));
        }
    }
    // Boot-seed / serial Minimal must remain free of these modules when validated separately.
    Ok(())
}

/// Pack graphics preview initramfs from init + console + graphics-demo static binaries.
///
/// When `modules_root` is `Some`, packs the allowlisted Alpine virt DRM modules (014.1).
pub fn pack_ryoku_graphics_from_paths(
    init_path: &Path,
    console_path: &Path,
    graphics_demo_path: &Path,
    release_text: &str,
) -> Result<Vec<u8>, String> {
    pack_ryoku_graphics_from_paths_with_modules(
        init_path,
        console_path,
        graphics_demo_path,
        release_text,
        None,
    )
}

/// Pack graphics preview; optionally include DRM modules from `modules_root`.
pub fn pack_ryoku_graphics_from_paths_with_modules(
    init_path: &Path,
    console_path: &Path,
    graphics_demo_path: &Path,
    release_text: &str,
    modules_root: Option<&Path>,
) -> Result<Vec<u8>, String> {
    let init = fs::read(init_path).map_err(|e| format!("read init: {e}"))?;
    let console = fs::read(console_path).map_err(|e| format!("read console: {e}"))?;
    let demo = fs::read(graphics_demo_path).map_err(|e| format!("read graphics-demo: {e}"))?;
    if init.is_empty() || console.is_empty() || demo.is_empty() {
        return Err("init/console/graphics-demo binary empty".into());
    }
    let mut out = Vec::new();
    match modules_root {
        Some(root) => {
            write_ryoku_graphics_newc_with_modules(
                &init,
                &console,
                &demo,
                release_text,
                root,
                &mut out,
            )?;
            validate_ryoku_graphics_cpio_with_modules(&out)?;
        }
        None => {
            write_ryoku_graphics_newc(&init, &console, &demo, release_text, &mut out)
                .map_err(|e| e.to_string())?;
            validate_ryoku_graphics_cpio(&out)?;
        }
    }
    Ok(out)
}

/// Validate shell preview cpio (Minimal + shell binary; must not include graphics-demo).
pub fn validate_ryoku_shell_cpio(data: &[u8]) -> Result<(), String> {
    validate_ryoku_minimal_cpio(data)?;
    let members = list_newc_members(data)?;
    if !members.iter().any(|m| m == REQUIRED_SHELL_PREVIEW_MEMBER) {
        return Err(format!("missing {REQUIRED_SHELL_PREVIEW_MEMBER}"));
    }
    if members.iter().any(|m| m == REQUIRED_GRAPHICS_DEMO_MEMBER) {
        return Err("shell package must not contain ryoku-graphics-demo (dual FB)".into());
    }
    Ok(())
}

/// Validate shell cpio including DRM modules.
pub fn validate_ryoku_shell_cpio_with_modules(data: &[u8]) -> Result<(), String> {
    validate_ryoku_shell_cpio(data)?;
    let members = list_newc_members(data)?;
    for req in REQUIRED_GRAPHICS_MODULE_MEMBERS {
        if !members.iter().any(|m| m == req) {
            return Err(format!("missing graphics module member {req}"));
        }
    }
    Ok(())
}

/// Write shell-preview newc (uncompressed).
pub fn write_ryoku_shell_newc(
    init_bytes: &[u8],
    console_bytes: &[u8],
    shell_preview_bytes: &[u8],
    release_text: &str,
    out: &mut dyn Write,
) -> io::Result<()> {
    write_newc_archive(
        &ryoku_shell_members(init_bytes, console_bytes, shell_preview_bytes, release_text),
        out,
    )
}

/// Write shell-preview newc including DRM modules.
pub fn write_ryoku_shell_newc_with_modules(
    init_bytes: &[u8],
    console_bytes: &[u8],
    shell_preview_bytes: &[u8],
    release_text: &str,
    modules_root: &Path,
    out: &mut dyn Write,
) -> Result<(), String> {
    let mut members =
        ryoku_shell_members(init_bytes, console_bytes, shell_preview_bytes, release_text);
    append_graphics_modules(&mut members, modules_root)?;
    write_newc_archive(&members, out).map_err(|e| e.to_string())
}

/// Pack shell preview initramfs (+ optional DRM modules).
pub fn pack_ryoku_shell_from_paths_with_modules(
    init_path: &Path,
    console_path: &Path,
    shell_preview_path: &Path,
    release_text: &str,
    modules_root: Option<&Path>,
) -> Result<Vec<u8>, String> {
    let init = fs::read(init_path).map_err(|e| format!("read init: {e}"))?;
    let console = fs::read(console_path).map_err(|e| format!("read console: {e}"))?;
    let shell = fs::read(shell_preview_path).map_err(|e| format!("read shell-preview: {e}"))?;
    if init.is_empty() || console.is_empty() || shell.is_empty() {
        return Err("init/console/shell-preview binary empty".into());
    }
    let mut out = Vec::new();
    match modules_root {
        Some(root) => {
            write_ryoku_shell_newc_with_modules(
                &init,
                &console,
                &shell,
                release_text,
                root,
                &mut out,
            )?;
            validate_ryoku_shell_cpio_with_modules(&out)?;
        }
        None => {
            write_ryoku_shell_newc(&init, &console, &shell, release_text, &mut out)
                .map_err(|e| e.to_string())?;
            validate_ryoku_shell_cpio(&out)?;
        }
    }
    Ok(out)
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
        assert!(listing_has_init(&members.join("\n")));
    }

    #[test]
    fn boot_seed_has_executable_init_and_console_5_1() {
        let mut buf = Vec::new();
        write_boot_seed_newc(b"FAKE_INIT_BYTES", &mut buf).unwrap();
        validate_boot_seed_cpio(&buf).unwrap();
        let parsed = parse_newc_members(&buf).unwrap();
        assert!(listing_has_console(
            &parsed
                .iter()
                .map(|m| m.name.as_str())
                .collect::<Vec<_>>()
                .join("\n")
        ));
        let console = parsed.iter().find(|m| m.name == "./dev/console").unwrap();
        assert_eq!(console.rmajor, 5);
        assert_eq!(console.rminor, 1);
        assert_eq!(console.mode & S_IFCHR, S_IFCHR);
        let init = parsed.iter().find(|m| m.name == "./init").unwrap();
        assert_ne!(init.mode & 0o111, 0);
        // No unexpected external-looking paths
        for m in &parsed {
            assert!(!m.name.contains(".."));
            assert!(!m.name.starts_with('/'));
        }
    }

    #[test]
    fn validate_rejects_missing_console() {
        let mut buf = Vec::new();
        write_newc_single_init(b"x", &mut buf).unwrap();
        assert!(validate_boot_seed_cpio(&buf)
            .unwrap_err()
            .contains("console"));
    }

    #[test]
    fn boot_seed_rejects_console_binary() {
        let mut buf = Vec::new();
        write_ryoku_minimal_newc(b"INIT", b"CONSOLE", RYOKU_RELEASE_TEXT, &mut buf).unwrap();
        assert!(validate_boot_seed_cpio(&buf)
            .unwrap_err()
            .contains("ryoku-console"));
    }

    #[test]
    fn ryoku_graphics_has_demo_binary() {
        let mut buf = Vec::new();
        write_ryoku_graphics_newc(
            b"INIT",
            b"CONSOLE",
            b"GFXDEMO",
            RYOKU_GRAPHICS_RELEASE_TEXT,
            &mut buf,
        )
        .unwrap();
        validate_ryoku_graphics_cpio(&buf).unwrap();
        let members = list_newc_members(&buf).unwrap();
        assert!(members.iter().any(|m| m == REQUIRED_GRAPHICS_DEMO_MEMBER));
        // Still validates as Minimal layout too.
        validate_ryoku_minimal_cpio(&buf).unwrap();
        // Without modules_root, DRM kos are absent (014.0 layout still valid).
        assert!(validate_ryoku_graphics_cpio_with_modules(&buf).is_err());
    }

    #[test]
    fn ryoku_graphics_with_modules_packs_allowlist() {
        let dir = env::temp_dir().join(format!(
            "ryoku-gfx-mods-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let _ = fs::remove_dir_all(&dir);
        for member in REQUIRED_GRAPHICS_MODULE_MEMBERS {
            let rel = member
                .strip_prefix("./lib/modules/6.12.114-0-virt/")
                .unwrap();
            let path = dir.join(rel);
            fs::create_dir_all(path.parent().unwrap()).unwrap();
            fs::write(&path, format!("FAKE_KO:{rel}")).unwrap();
        }
        let mut buf = Vec::new();
        write_ryoku_graphics_newc_with_modules(
            b"INIT",
            b"CONSOLE",
            b"GFXDEMO",
            RYOKU_GRAPHICS_RELEASE_TEXT,
            &dir,
            &mut buf,
        )
        .unwrap();
        validate_ryoku_graphics_cpio_with_modules(&buf).unwrap();
        let members = list_newc_members(&buf).unwrap();
        assert!(members.iter().any(|m| m == REQUIRED_GRAPHICS_DEMO_MEMBER));
        for req in REQUIRED_GRAPHICS_MODULE_MEMBERS {
            assert!(members.iter().any(|m| m == req), "missing {req}");
        }
        // Serial Minimal validator still OK (extra members allowed for Minimal check).
        validate_ryoku_minimal_cpio(&buf).unwrap();
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn append_modules_rejects_missing_allowlist_file() {
        let dir = env::temp_dir().join(format!("ryoku-gfx-mods-empty-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let mut members = Vec::new();
        let err = append_graphics_modules(&mut members, &dir).unwrap_err();
        assert!(err.contains("missing allowlisted"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn ryoku_shell_has_preview_not_graphics_demo() {
        let mut buf = Vec::new();
        write_ryoku_shell_newc(
            b"INIT",
            b"CONSOLE",
            b"SHELL",
            RYOKU_SHELL_RELEASE_TEXT,
            &mut buf,
        )
        .unwrap();
        validate_ryoku_shell_cpio(&buf).unwrap();
        let members = list_newc_members(&buf).unwrap();
        assert!(members.iter().any(|m| m == REQUIRED_SHELL_PREVIEW_MEMBER));
        assert!(!members.iter().any(|m| m == REQUIRED_GRAPHICS_DEMO_MEMBER));
    }

    #[test]
    fn ryoku_minimal_has_required_layout() {
        let mut buf = Vec::new();
        write_ryoku_minimal_newc(
            b"INIT_BYTES",
            b"CONSOLE_BYTES",
            RYOKU_RELEASE_TEXT,
            &mut buf,
        )
        .unwrap();
        validate_ryoku_minimal_cpio(&buf).unwrap();
        let parsed = parse_newc_members(&buf).unwrap();
        let names: Vec<_> = parsed.iter().map(|m| m.name.as_str()).collect();
        assert!(names.contains(&"./init"));
        assert!(names.contains(&"./bin/ryoku-console"));
        assert!(names.contains(&"./dev/console"));
        assert!(names.contains(&"./etc/ryoku-release"));
        assert!(names.contains(&"./home/ryoku"));
        let bin = parsed
            .iter()
            .find(|m| m.name == "./bin/ryoku-console")
            .unwrap();
        assert_ne!(bin.mode & 0o111, 0);
        assert_eq!(bin.filesize, "CONSOLE_BYTES".len() as u32);
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
