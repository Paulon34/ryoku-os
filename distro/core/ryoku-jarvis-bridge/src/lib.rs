//! Jarvis bridge — opt-in assistant hook for Ryoku Debian.
//!
//! Default policy: **disabled**. Minimal profiles must keep Jarvis off unless
//! the user explicitly enables it (`RYOKU_JARVIS=1` or `ryoku jarvis-bridge enable`).

use std::env;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

/// Marker file under XDG config that records an explicit enable.
pub fn marker_path() -> PathBuf {
    let base = env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            let home = env::var_os("HOME").unwrap_or_else(|| ".".into());
            PathBuf::from(home).join(".config")
        });
    base.join("ryoku").join("jarvis.enabled")
}

/// True when Jarvis should run.
///
/// Order: explicit disable env → marker/enable env → default false.
pub fn is_enabled() -> bool {
    match env::var("RYOKU_JARVIS").ok().as_deref() {
        Some("0") | Some("false") | Some("off") => return false,
        Some("1") | Some("true") | Some("on") => return true,
        Some(_) | None => {}
    }
    marker_path().is_file()
}

pub fn enable() -> io::Result<()> {
    let path = marker_path();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(&path, b"1\n")?;
    Ok(())
}

pub fn disable() -> io::Result<()> {
    let path = marker_path();
    match fs::remove_file(&path) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(e),
    }
}

/// Placeholder bridge status — no network calls; no model invocation.
pub fn status_report() -> String {
    if is_enabled() {
        format!(
            "jarvis: enabled (marker {})\nbridge: idle (no daemon in ENTREGA D stub)",
            marker_path().display()
        )
    } else {
        "jarvis: disabled (default)\nhint: ryoku jarvis-bridge enable   # or RYOKU_JARVIS=1".into()
    }
}

/// Read profile.json jarvis flag if present (informational).
pub fn profile_jarvis_flag(config_home: &Path) -> Option<bool> {
    let path = config_home.join("ryoku").join("profile.json");
    let text = fs::read_to_string(path).ok()?;
    // Tiny parse without serde: look for `"jarvis": true/false`.
    if text.contains("\"jarvis\": true") || text.contains("\"jarvis\":true") {
        Some(true)
    } else if text.contains("\"jarvis\": false") || text.contains("\"jarvis\":false") {
        Some(false)
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    static ENV_LOCK: Mutex<()> = Mutex::new(());

    #[test]
    fn default_disabled_without_env_or_marker() {
        let _g = ENV_LOCK.lock().unwrap();
        env::remove_var("RYOKU_JARVIS");
        // marker may exist on developer machines — isolate via temp HOME.
        let tmp = tempfile_home();
        env::set_var("HOME", &tmp);
        env::remove_var("XDG_CONFIG_HOME");
        assert!(!is_enabled());
        let _ = fs::remove_dir_all(tmp);
    }

    #[test]
    fn env_on_enables() {
        let _g = ENV_LOCK.lock().unwrap();
        let tmp = tempfile_home();
        env::set_var("HOME", &tmp);
        env::remove_var("XDG_CONFIG_HOME");
        env::set_var("RYOKU_JARVIS", "1");
        assert!(is_enabled());
        env::remove_var("RYOKU_JARVIS");
        let _ = fs::remove_dir_all(tmp);
    }

    fn tempfile_home() -> PathBuf {
        let mut p = env::temp_dir();
        p.push(format!("ryoku-jarvis-test-{}", std::process::id()));
        let _ = fs::create_dir_all(&p);
        p
    }
}
