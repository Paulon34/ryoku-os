//! Safe QEMU argv construction — never a shell string.

use crate::config::{AccelMode, NetworkMode, VmConfig};
use crate::tools::AccelChoice;

/// Built argv ready for `Command::new(&argv[0]).args(&argv[1..])`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct QemuArgv {
    pub program: String,
    pub args: Vec<String>,
    pub accel_used: AccelChoice,
}

impl QemuArgv {
    /// Full argv including program at index 0 (handy for logging).
    #[must_use]
    pub fn as_command_line_parts(&self) -> Vec<String> {
        let mut all = Vec::with_capacity(1 + self.args.len());
        all.push(self.program.clone());
        all.extend(self.args.clone());
        all
    }
}

/// Build a disposable, isolated QEMU argv from a validated config + accel decision.
///
/// Defaults:
/// - no host network (`-netdev none` is not portable everywhere; we use `-nic none`)
/// - no default devices that pull host peripherals (`-nodefaults` + explicit virtio when disk set)
/// - display none / nographic for headless lab
pub fn build_qemu_argv(
    qemu_bin: &str,
    cfg: &VmConfig,
    accel: AccelChoice,
) -> Result<QemuArgv, String> {
    match (cfg.accel, accel) {
        (AccelMode::Kvm, AccelChoice::Tcg) => {
            return Err("config requires KVM but only TCG is available".to_string());
        }
        (AccelMode::Tcg, AccelChoice::Kvm) => {
            // Caller should have selected TCG; refuse inconsistent pairing.
            return Err("internal: TCG config paired with KVM accel choice".to_string());
        }
        _ => {}
    }

    let mut args: Vec<String> = Vec::new();
    args.push("-name".into());
    args.push(format!("ryoku-virtlab-{}", sanitize_name(&cfg.name)));

    args.push("-accel".into());
    args.push(match accel {
        AccelChoice::Kvm => "kvm".into(),
        AccelChoice::Tcg => "tcg".into(),
    });

    args.push("-m".into());
    args.push(cfg.memory_mb.to_string());
    args.push("-smp".into());
    args.push(cfg.cpus.to_string());

    args.push("-display".into());
    args.push("none".into());
    args.push("-nographic".into());
    args.push("-nodefaults".into());

    // No host network by default.
    match cfg.network {
        NetworkMode::None => {
            args.push("-nic".into());
            args.push("none".into());
        }
    }

    // No physical CDROM/USB; only optional disposable disk/kernel under lab dirs.
    if let Some(disk) = &cfg.disk {
        args.push("-drive".into());
        args.push(format!(
            "file={},if=virtio,format=qcow2,media=disk,snapshot=on",
            disk.display()
        ));
    }

    if let Some(kernel) = &cfg.kernel {
        args.push("-kernel".into());
        args.push(kernel.display().to_string());
    }

    // Emulator-only smoke: machine with no bootable medium. QEMU may exit or wait;
    // the executor applies timeout. We still never claim OS boot for this mode.
    if cfg.is_emulator_only() {
        args.push("-machine".into());
        args.push("type=none".into());
        // Monitor for a clean quit path if the process stays up; T1 may send "quit\n".
        args.push("-monitor".into());
        args.push("stdio".into());
    }

    Ok(QemuArgv {
        program: qemu_bin.to_string(),
        args,
        accel_used: accel,
    })
}

fn sanitize_name(name: &str) -> String {
    name.chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '-' || c == '_' {
                c
            } else {
                '-'
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{AccelMode, NetworkMode, VmConfig};
    use std::path::PathBuf;

    fn base_cfg() -> VmConfig {
        VmConfig {
            name: "smoke".to_string(),
            memory_mb: 256,
            cpus: 1,
            timeout_secs: 10,
            accel: AccelMode::Tcg,
            network: NetworkMode::None,
            disk: None,
            kernel: None,
        }
    }

    #[test]
    fn argv_has_no_shell_metacharacters_joined_unsafely() {
        let argv = build_qemu_argv("qemu-system-x86_64", &base_cfg(), AccelChoice::Tcg).unwrap();
        assert_eq!(argv.program, "qemu-system-x86_64");
        assert!(argv.args.iter().any(|a| a == "-accel"));
        assert!(argv.args.iter().any(|a| a == "tcg"));
        assert!(argv.args.iter().any(|a| a == "-nic"));
        assert!(argv.args.iter().any(|a| a == "none"));
        // Never a single shell string — each flag is its own element.
        assert!(!argv
            .args
            .iter()
            .any(|a| a.contains("&&") || a.contains('|')));
    }

    #[test]
    fn rejects_kvm_config_when_only_tcg() {
        let mut cfg = base_cfg();
        cfg.accel = AccelMode::Kvm;
        let err = build_qemu_argv("qemu-system-x86_64", &cfg, AccelChoice::Tcg).unwrap_err();
        assert!(err.contains("requires KVM"));
    }

    #[test]
    fn disk_path_is_separate_arg_value() {
        let mut cfg = base_cfg();
        cfg.disk = Some(PathBuf::from("/workspace/tests/qemu/run/disk.qcow2"));
        cfg.kernel = None;
        // Not emulator-only anymore — skip machine none
        let argv = build_qemu_argv("qemu-system-x86_64", &cfg, AccelChoice::Tcg).unwrap();
        assert!(argv
            .args
            .iter()
            .any(|a| a.contains("/workspace/tests/qemu/run/disk.qcow2")));
        assert!(!argv.args.iter().any(|a| a == "type=none"));
    }
}
