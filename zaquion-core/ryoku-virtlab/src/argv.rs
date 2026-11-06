//! Safe QEMU argv construction — never a shell string.

use crate::config::{AccelMode, NetworkMode, ShutdownMode, VmConfig};
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
/// - no host network (`-nic none`)
/// - display none / nographic for headless lab
/// - serial to a lab `results/` file when configured; monitor on stdio for quit
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

    match cfg.network {
        NetworkMode::None => {
            args.push("-nic".into());
            args.push("none".into());
        }
    }

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

    if let Some(iso) = &cfg.iso {
        // IDE CD for broad QEMU compatibility with ISO boot.
        args.push("-drive".into());
        args.push(format!(
            "file={},media=cdrom,readonly=on,if=ide",
            iso.display()
        ));
        args.push("-boot".into());
        args.push("order=d".into());
    }

    if let Some(serial) = &cfg.serial_log {
        args.push("-serial".into());
        args.push(format!("file:{}", serial.display()));
    }

    if cfg.is_emulator_only() {
        args.push("-machine".into());
        args.push("type=none".into());
    } else {
        // Explicit PC machine for ISO/disk boots (TCG/KVM).
        args.push("-machine".into());
        args.push("type=pc".into());
    }

    // Monitor on stdio enables controlled shutdown via `quit` without a shell wrapper.
    if matches!(cfg.shutdown, ShutdownMode::MonitorQuit) || cfg.is_emulator_only() {
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
    use crate::config::{AccelMode, NetworkMode, ShutdownMode, VmConfig};
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
            iso: None,
            serial_log: None,
            boot_sentinel: None,
            shutdown: ShutdownMode::MonitorQuit,
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
    fn iso_boot_uses_cdrom_and_serial_file() {
        let mut cfg = base_cfg();
        cfg.iso = Some(PathBuf::from("/workspace/tests/qemu/run/alpine.iso"));
        cfg.serial_log = Some(PathBuf::from("/workspace/tests/qemu/results/serial-t2.log"));
        let argv = build_qemu_argv("qemu-system-x86_64", &cfg, AccelChoice::Tcg).unwrap();
        let joined = argv.as_command_line_parts().join(" ");
        assert!(joined.contains("media=cdrom"));
        assert!(joined.contains("order=d"));
        assert!(joined.contains("file:/workspace/tests/qemu/results/serial-t2.log"));
        assert!(!joined.contains("type=none"));
        assert!(joined.contains("type=pc"));
    }
}
