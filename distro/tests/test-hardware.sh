#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
probe="$ROOT/distro/scripts/ryoku-hardware"
bash -n "$probe"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/proc" "$tmp/sys/bus/pci/devices" "$tmp/sys/bus/usb/devices"
pci() {
  local path="$tmp/sys/bus/pci/devices/$1"
  mkdir -p "$path"
  printf '%s\n' "$2" >"$path/vendor"
  printf '%s\n' "$3" >"$path/class"
}
check() {
  local expected=$1 flag=$2
  [[ "$(bash "$probe" --sysroot "$tmp" "$flag")" == "$expected" ]]
}
printf 'vendor_id : GenuineIntel\n' >"$tmp/proc/cpuinfo"
printf 'MemTotal: 16000000 kB\n' >"$tmp/proc/meminfo"
pci 0000:00:02.0 0x8086 0x030000
pci 0000:01:00.0 0x10de 0x030200
pci 0000:00:14.3 0x8086 0x028000
check hybrid-nvidia --gpu
check balanced --visual
out=$(bash "$probe" --sysroot "$tmp" --packages)
for p in intel-microcode firmware-intel-graphics intel-media-va-driver firmware-nvidia-graphics firmware-iwlwifi; do
  grep -Fxq "$p" <<<"$out"
done
! grep -Eq '^nvidia-driver$|^amd64-microcode$' <<<"$out"
echo "PASS: Intel hybrid NVIDIA laptop detection"
rm -rf "$tmp/sys/bus/pci/devices/"*
printf 'vendor_id : AuthenticAMD\n' >"$tmp/proc/cpuinfo"
pci 0000:01:00.0 0x1002 0x030000
pci 0000:02:00.0 0x14c3 0x028000
check amd --gpu
out=$(bash "$probe" --sysroot "$tmp" --packages)
for p in amd64-microcode firmware-amd-graphics mesa-va-drivers firmware-mediatek; do
  grep -Fxq "$p" <<<"$out"
done
! grep -qi nvidia <<<"$out"
echo "PASS: AMD desktop detection"
printf 'MemTotal: 4000000 kB\n' >"$tmp/proc/meminfo"
check lite --visual
rm -rf "$tmp/sys/bus/pci/devices/"*
pci 0000:00:02.0 0x1234 0x030000
check virtual --gpu
check lite --visual
out=$(bash "$probe" --sysroot "$tmp" --packages)
! grep -Eq 'microcode|nvidia-driver' <<<"$out"
echo "PASS: low-memory VM excludes proprietary GPU drivers"
bash -n "$ROOT/distro/scripts/ryoku-bootstrap"
bash -n "$ROOT/distro/scripts/ryoku-flatpak-sync"
echo "PASS_STATIC: hardware selection (fixtures only, no APT mutations)"
