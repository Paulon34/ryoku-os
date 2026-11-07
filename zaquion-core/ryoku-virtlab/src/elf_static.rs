//! Static ELF proof for Boot Seed `/init` (Mission 008.5 final fixes).
//!
//! Pure byte analysis — **does not** use `ldd` (which can execute/interpret loaders).
//! Fail-closed: anything unproven is rejected for T3 packing.

#![allow(clippy::unreadable_literal)]

use std::fs;
use std::path::Path;

/// ELF magic.
const ELFMAG: [u8; 4] = [0x7f, b'E', b'L', b'F'];
const ELFCLASS64: u8 = 2;
const ELFDATA2LSB: u8 = 1;
const EM_X86_64: u16 = 62;
const ET_EXEC: u16 = 2;
const ET_DYN: u16 = 3; // PIE still OK if no interpreter / DT_NEEDED
const PT_INTERP: u32 = 3;
const PT_DYNAMIC: u32 = 2;
const SHT_DYNAMIC: u32 = 6;
const DT_NULL: u64 = 0;
const DT_NEEDED: u64 = 1;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ElfStaticError {
    Io(String),
    TooSmall,
    NotElf,
    NotElf64,
    NotLittleEndian,
    NotX86_64 { machine: u16 },
    BadType { etype: u16 },
    Truncated(&'static str),
    HasPtInterp,
    HasDtNeeded { count: usize },
}

impl std::fmt::Display for ElfStaticError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io(e) => write!(f, "io: {e}"),
            Self::TooSmall => write!(f, "file too small for ELF header"),
            Self::NotElf => write!(f, "not an ELF file"),
            Self::NotElf64 => write!(f, "not ELFCLASS64"),
            Self::NotLittleEndian => write!(f, "not little-endian ELF"),
            Self::NotX86_64 { machine } => write!(f, "not EM_X86_64 (machine={machine})"),
            Self::BadType { etype } => write!(f, "unsupported e_type={etype}"),
            Self::Truncated(what) => write!(f, "truncated ELF ({what})"),
            Self::HasPtInterp => write!(f, "PT_INTERP present (dynamically linked)"),
            Self::HasDtNeeded { count } => {
                write!(f, "DT_NEEDED present ({count} entries) — not fully static")
            }
        }
    }
}

impl std::error::Error for ElfStaticError {}

/// Prove `path` is a statically linked little-endian x86_64 ELF suitable for bare `/init`.
pub fn prove_static_x86_64_elf(path: &Path) -> Result<(), ElfStaticError> {
    let bytes = fs::read(path).map_err(|e| ElfStaticError::Io(e.to_string()))?;
    prove_static_x86_64_elf_bytes(&bytes)
}

/// Same checks on an in-memory buffer (unit tests).
pub fn prove_static_x86_64_elf_bytes(bytes: &[u8]) -> Result<(), ElfStaticError> {
    if bytes.len() < 64 {
        return Err(ElfStaticError::TooSmall);
    }
    if bytes[0..4] != ELFMAG {
        return Err(ElfStaticError::NotElf);
    }
    if bytes[4] != ELFCLASS64 {
        return Err(ElfStaticError::NotElf64);
    }
    if bytes[5] != ELFDATA2LSB {
        return Err(ElfStaticError::NotLittleEndian);
    }

    let etype = u16::from_le_bytes([bytes[16], bytes[17]]);
    if etype != ET_EXEC && etype != ET_DYN {
        return Err(ElfStaticError::BadType { etype });
    }
    let machine = u16::from_le_bytes([bytes[18], bytes[19]]);
    if machine != EM_X86_64 {
        return Err(ElfStaticError::NotX86_64 { machine });
    }

    let phoff = u64::from_le_bytes(bytes[32..40].try_into().unwrap()) as usize;
    let phentsize = u16::from_le_bytes([bytes[54], bytes[55]]) as usize;
    let phnum = u16::from_le_bytes([bytes[56], bytes[57]]) as usize;
    if phentsize < 56 {
        return Err(ElfStaticError::Truncated("phentsize"));
    }

    let mut saw_dynamic_phdr = false;
    for i in 0..phnum {
        let off = phoff
            .checked_add(
                i.checked_mul(phentsize)
                    .ok_or(ElfStaticError::Truncated("ph table"))?,
            )
            .ok_or(ElfStaticError::Truncated("ph table"))?;
        if off + 56 > bytes.len() {
            return Err(ElfStaticError::Truncated("program header"));
        }
        let p_type = u32::from_le_bytes(bytes[off..off + 4].try_into().unwrap());
        if p_type == PT_INTERP {
            return Err(ElfStaticError::HasPtInterp);
        }
        if p_type == PT_DYNAMIC {
            saw_dynamic_phdr = true;
            let p_offset =
                u64::from_le_bytes(bytes[off + 8..off + 16].try_into().unwrap()) as usize;
            let p_filesz =
                u64::from_le_bytes(bytes[off + 32..off + 40].try_into().unwrap()) as usize;
            let needed = count_dt_needed(bytes, p_offset, p_filesz)?;
            if needed > 0 {
                return Err(ElfStaticError::HasDtNeeded { count: needed });
            }
        }
    }

    // Also scan SHT_DYNAMIC if present (covers odd layouts without relying on PT_DYNAMIC alone).
    let shoff = u64::from_le_bytes(bytes[40..48].try_into().unwrap()) as usize;
    let shentsize = u16::from_le_bytes([bytes[58], bytes[59]]) as usize;
    let shnum = u16::from_le_bytes([bytes[60], bytes[61]]) as usize;
    if shnum > 0 && shentsize >= 64 && shoff > 0 {
        for i in 0..shnum {
            let off = match shoff.checked_add(i.checked_mul(shentsize).unwrap_or(usize::MAX)) {
                Some(o) => o,
                None => break,
            };
            if off + 64 > bytes.len() {
                break;
            }
            let sh_type = u32::from_le_bytes(bytes[off + 4..off + 8].try_into().unwrap());
            if sh_type == SHT_DYNAMIC {
                let sh_offset =
                    u64::from_le_bytes(bytes[off + 24..off + 32].try_into().unwrap()) as usize;
                let sh_size =
                    u64::from_le_bytes(bytes[off + 32..off + 40].try_into().unwrap()) as usize;
                let needed = count_dt_needed(bytes, sh_offset, sh_size)?;
                if needed > 0 {
                    return Err(ElfStaticError::HasDtNeeded { count: needed });
                }
            }
        }
    } else if saw_dynamic_phdr {
        // Already inspected via PT_DYNAMIC.
    }

    Ok(())
}

fn count_dt_needed(bytes: &[u8], offset: usize, size: usize) -> Result<usize, ElfStaticError> {
    if size == 0 {
        return Ok(0);
    }
    if offset
        .checked_add(size)
        .map(|e| e > bytes.len())
        .unwrap_or(true)
    {
        return Err(ElfStaticError::Truncated("dynamic segment"));
    }
    let mut needed = 0usize;
    let mut i = 0usize;
    while i + 16 <= size {
        let tag = u64::from_le_bytes(bytes[offset + i..offset + i + 8].try_into().unwrap());
        if tag == DT_NULL {
            break;
        }
        if tag == DT_NEEDED {
            needed += 1;
        }
        i += 16;
    }
    Ok(needed)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn minimal_elf64(machine: u16, etype: u16, with_interp: bool) -> Vec<u8> {
        // Extremely small synthetic ELF64 LE for unit tests (not a runnable binary).
        let mut b = vec![0u8; 256];
        b[0..4].copy_from_slice(&ELFMAG);
        b[4] = ELFCLASS64;
        b[5] = ELFDATA2LSB;
        b[6] = 1; // EV_CURRENT
        b[16..18].copy_from_slice(&etype.to_le_bytes());
        b[18..20].copy_from_slice(&machine.to_le_bytes());
        // e_phoff = 64, e_phentsize = 56, e_phnum = 1 or 2
        b[32..40].copy_from_slice(&64u64.to_le_bytes());
        b[54..56].copy_from_slice(&56u16.to_le_bytes());
        b[56..58].copy_from_slice(&1u16.to_le_bytes());
        // e_shoff = 0, no sections
        b[40..48].copy_from_slice(&0u64.to_le_bytes());
        b[58..60].copy_from_slice(&64u16.to_le_bytes());
        b[60..62].copy_from_slice(&0u16.to_le_bytes());
        // Program header at 64
        let p_type = if with_interp { PT_INTERP } else { 1u32 }; // PT_LOAD=1
        b[64..68].copy_from_slice(&p_type.to_le_bytes());
        b
    }

    #[test]
    fn accepts_static_looking_x86_64() {
        let b = minimal_elf64(EM_X86_64, ET_EXEC, false);
        assert!(prove_static_x86_64_elf_bytes(&b).is_ok());
    }

    #[test]
    fn rejects_pt_interp() {
        let b = minimal_elf64(EM_X86_64, ET_DYN, true);
        assert!(matches!(
            prove_static_x86_64_elf_bytes(&b),
            Err(ElfStaticError::HasPtInterp)
        ));
    }

    #[test]
    fn rejects_wrong_arch() {
        let b = minimal_elf64(3, ET_EXEC, false); // EM_386
        assert!(matches!(
            prove_static_x86_64_elf_bytes(&b),
            Err(ElfStaticError::NotX86_64 { .. })
        ));
    }

    #[test]
    fn rejects_invalid_and_too_small() {
        assert!(matches!(
            prove_static_x86_64_elf_bytes(b"not elf"),
            Err(ElfStaticError::TooSmall)
        ));
        let mut b = vec![0u8; 64];
        b[0..4].copy_from_slice(b"AAAA");
        assert!(matches!(
            prove_static_x86_64_elf_bytes(&b),
            Err(ElfStaticError::NotElf)
        ));
    }

    #[test]
    fn rejects_dt_needed_in_dynamic() {
        let mut b = minimal_elf64(EM_X86_64, ET_DYN, false);
        // Expand and add PT_DYNAMIC pointing at a DT_NEEDED entry.
        b.resize(512, 0);
        b[56..58].copy_from_slice(&2u16.to_le_bytes()); // phnum=2
                                                        // ph[1] at 64+56=120
        let off = 120;
        b[off..off + 4].copy_from_slice(&PT_DYNAMIC.to_le_bytes());
        let dyn_off = 200u64;
        b[off + 8..off + 16].copy_from_slice(&dyn_off.to_le_bytes());
        b[off + 32..off + 40].copy_from_slice(&32u64.to_le_bytes()); // filesz
                                                                     // dynamic entries at 200: DT_NEEDED, DT_NULL
        let d = dyn_off as usize;
        b[d..d + 8].copy_from_slice(&DT_NEEDED.to_le_bytes());
        b[d + 8..d + 16].copy_from_slice(&1u64.to_le_bytes());
        b[d + 16..d + 24].copy_from_slice(&DT_NULL.to_le_bytes());
        assert!(matches!(
            prove_static_x86_64_elf_bytes(&b),
            Err(ElfStaticError::HasDtNeeded { count: 1 })
        ));
    }

    #[test]
    fn host_debug_ryoku_init_is_dynamic_if_present() {
        // Integration-ish: the gnu-linked debug binary (if built) must be rejected.
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../target/debug/ryoku-init");
        if path.is_file() {
            let err = prove_static_x86_64_elf(&path).unwrap_err();
            assert!(
                matches!(
                    err,
                    ElfStaticError::HasPtInterp | ElfStaticError::HasDtNeeded { .. }
                ),
                "unexpected: {err}"
            );
        }
    }
}
