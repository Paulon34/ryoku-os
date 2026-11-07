//! Lab root discovery — always returns an absolute, lexically normalized path.
//!
//! Relative discovery (e.g. `../tests/qemu` from `zaquion-core/`) must not later
//! lose `..` during asset joins. Callers should pass the absolute lab root into
//! `security::validate_optional_path`.

use std::path::{Path, PathBuf};

use crate::security::{absolute_from, normalize_lexically, safe_canonicalize_existing};

/// Discover the Virtual Lab root (`tests/qemu`) as an **absolute** path.
///
/// `cwd` is the process working directory (injected for tests — no global cwd mutation).
/// `crate_manifest_dir` is typically `env!("CARGO_MANIFEST_DIR")` for the virtlab crate.
#[must_use]
pub fn discover_lab_root_from(cwd: &Path, crate_manifest_dir: &Path) -> PathBuf {
    // Prefer the crate-relative lab (stable across cwd), then cwd-relative lookups.
    // Absolutize before accepting so `../tests/qemu` never later collapses under
    // `zaquion-core/` during asset joins.
    let candidates = [
        crate_manifest_dir.join("../../tests/qemu"),
        cwd.join("tests/qemu"),
        cwd.join("../tests/qemu"),
    ];
    for cand in &candidates {
        let abs = if cand.is_absolute() {
            normalize_lexically(cand)
        } else {
            absolute_from(cwd, cand)
        };
        if abs.join("configs").is_dir() || abs.join("fixtures").is_dir() {
            return safe_canonicalize_existing(&abs).unwrap_or(abs);
        }
    }
    // Fallback: absolute path under cwd (may not exist yet).
    absolute_from(cwd, Path::new("tests/qemu"))
}

/// Resolve a config-relative asset under an absolute lab root (test helper).
#[must_use]
pub fn resolve_lab_asset(lab_root_abs: &Path, rel: &str) -> PathBuf {
    normalize_lexically(&lab_root_abs.join(rel))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::sync::atomic::{AtomicU64, Ordering};

    static COUNTER: AtomicU64 = AtomicU64::new(0);

    fn temp_unique() -> PathBuf {
        let n = COUNTER.fetch_add(1, Ordering::SeqCst);
        std::env::temp_dir().join(format!("ryoku-lab-discover-{n}-{}", std::process::id()))
    }

    /// Build a mini lab tree without touching the process global cwd.
    fn make_lab_tree(root: &Path) {
        for sub in [
            "tests/qemu/configs",
            "tests/qemu/fixtures",
            "tests/qemu/run",
            "tests/qemu/results",
            "zaquion-core",
            "other/nested",
        ] {
            fs::create_dir_all(root.join(sub)).unwrap();
        }
        fs::write(root.join("tests/qemu/configs/dummy.rvl.conf"), "name = x\n").unwrap();
        fs::write(root.join("tests/qemu/run/fake-alpine.iso"), b"fake-iso").unwrap();
    }

    #[test]
    fn discovers_same_absolute_lab_from_repo_root_and_zaquion_core() {
        let root = temp_unique();
        make_lab_tree(&root);
        let manifest = root.join("zaquion-core/ryoku-virtlab");
        fs::create_dir_all(&manifest).unwrap();

        let from_root = discover_lab_root_from(&root, &manifest);
        let from_core = discover_lab_root_from(&root.join("zaquion-core"), &manifest);
        assert!(from_root.is_absolute());
        assert!(from_core.is_absolute());
        assert_eq!(from_root, from_core);
        assert!(from_root.ends_with("tests/qemu"));

        let iso_a = resolve_lab_asset(&from_root, "run/fake-alpine.iso");
        let iso_b = resolve_lab_asset(&from_core, "run/fake-alpine.iso");
        assert_eq!(iso_a, iso_b);
        assert!(iso_a.is_file());
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn discovers_from_nested_other_dir_via_manifest_fallback() {
        let root = temp_unique();
        make_lab_tree(&root);
        let manifest = root.join("zaquion-core/ryoku-virtlab");
        fs::create_dir_all(&manifest).unwrap();

        // cwd has no relative tests/qemu; manifest fallback still finds the lab.
        let from_other = discover_lab_root_from(&root.join("other/nested"), &manifest);
        assert!(from_other.is_absolute());
        assert!(from_other.join("run/fake-alpine.iso").is_file());
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn relative_parent_lab_does_not_collapse_to_wrong_tree() {
        let root = temp_unique();
        make_lab_tree(&root);
        // Wrong tree that would win if `../tests/qemu` were lexically collapsed to `tests/qemu`
        // under zaquion-core without absolutizing first.
        fs::create_dir_all(root.join("zaquion-core/tests/qemu/configs")).unwrap();
        fs::create_dir_all(root.join("zaquion-core/tests/qemu/run")).unwrap();
        fs::write(root.join("zaquion-core/tests/qemu/run/wrong.iso"), b"wrong").unwrap();

        let manifest = root.join("zaquion-core/ryoku-virtlab");
        fs::create_dir_all(&manifest).unwrap();
        let lab = discover_lab_root_from(&root.join("zaquion-core"), &manifest);
        let iso = resolve_lab_asset(&lab, "run/fake-alpine.iso");
        assert!(
            iso.is_file(),
            "must find the real lab ISO, not zaquion-core/tests/qemu"
        );
        assert!(!iso.ends_with("wrong.iso"));
        assert!(std::fs::read(&iso).unwrap() == b"fake-iso");
        let _ = fs::remove_dir_all(&root);
    }
}
