#!/usr/bin/env bash
# Exercises scripts/rpi-tftp-links, rpi-eeprom-build and rpi-recovery-image (no Pi or rpi-eeprom needed).
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# rpi-tftp-links
mkdir -p "$TMP/groups" "$TMP/tftp/rpi4"
echo '{"selector":{"mac":"E4:5F:01:23:F0:8E"}}' >"$TMP/groups/rpi4-a.json"
echo '{"selector":{"mac":"d8:3a:dd:63:11:e8"}}' >"$TMP/groups/rpi4-b.json"
echo '{"selector":{}}' >"$TMP/groups/default-x64.json"
"$HERE/../rpi-tftp-links" "$TMP/groups" "$TMP/tftp" >/dev/null
"$HERE/../rpi-tftp-links" "$TMP/groups" "$TMP/tftp" >/dev/null # idempotent
for d in e4-5f-01-23-f0-8e d8-3a-dd-63-11-e8; do
  [[ $(readlink "$TMP/tftp/$d") == rpi4 ]] || { echo "FAIL: missing link $d"; exit 1; }
done
[[ $(ls "$TMP/tftp" | wc -l) -eq 3 ]] || { echo "FAIL: unexpected entries"; exit 1; }

echo '{"selector":{}}' >"$TMP/groups/rpi4-bad.json"
if "$HERE/../rpi-tftp-links" "$TMP/groups" "$TMP/tftp" >/dev/null 2>&1; then
  echo "FAIL: group without mac was not fatal"; exit 1
fi

# rpi-eeprom-build
mkdir "$TMP/bin"
cat >"$TMP/bin/rpi-eeprom-config" <<'STUB'
#!/usr/bin/env bash
while [[ $# -gt 1 ]]; do
  case $1 in --out) out=$2; shift 2 ;; --config) conf=$2; shift 2 ;; *) shift ;; esac
done
{ cat "$conf"; cat "$1"; } >"$out"
STUB
chmod +x "$TMP/bin/rpi-eeprom-config"
echo bootloader >"$TMP/pieeprom.bin"
PATH="$TMP/bin:$PATH" "$HERE/../rpi-eeprom-build" "$TMP/pieeprom.bin" "$TMP/out" >/dev/null
grep -q '^TFTP_PREFIX=2$' "$TMP/out/pieeprom.upd" || { echo "FAIL: boot.conf not applied"; exit 1; }
[[ $(<"$TMP/out/pieeprom.sig") == "$(sha256sum "$TMP/out/pieeprom.upd" | cut -d' ' -f1)" ]] \
  || { echo "FAIL: bad pieeprom.sig"; exit 1; }
if "$HERE/../rpi-eeprom-build" >/dev/null 2>&1; then echo "FAIL: missing arg accepted"; exit 1; fi
if PATH="$TMP/bin:$PATH" "$HERE/../rpi-eeprom-build" "$TMP/missing.bin" "$TMP/out" >/dev/null 2>&1; then
  echo "FAIL: missing input accepted"; exit 1
fi

# rpi-recovery-image (mkfs.vfat and mcopy stubbed; mcopy records what it copies)
cat >"$TMP/bin/mkfs.vfat" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
cat >"$TMP/bin/mcopy" <<STUB
#!/usr/bin/env bash
shift 2
while [[ \$# -gt 1 ]]; do basename "\$1" >>"$TMP/copied"; shift; done
STUB
chmod +x "$TMP/bin/mkfs.vfat" "$TMP/bin/mcopy"
echo recovery >"$TMP/recovery.bin"
PATH="$TMP/bin:$PATH" "$HERE/../rpi-recovery-image" "$TMP/pieeprom.bin" "$TMP/recovery.bin" "$TMP/rec.img" >/dev/null
[[ -f $TMP/rec.img ]] || { echo "FAIL: no image"; exit 1; }
[[ $(sort "$TMP/copied" | tr '\n' ' ') == "pieeprom.sig pieeprom.upd recovery.bin " ]] \
  || { echo "FAIL: wrong files in recovery image"; exit 1; }
if PATH="$TMP/bin:$PATH" "$HERE/../rpi-recovery-image" "$TMP/pieeprom.bin" "$TMP/none.bin" "$TMP/x.img" >/dev/null 2>&1; then
  echo "FAIL: missing recovery.bin accepted"; exit 1
fi

# rpi4-uefi-defaults
cat >"$TMP/RPi4.dsc" <<'DSC'
  gRaspberryPiTokenSpaceGuid.PcdRamMoreThan3GB|L"RamMoreThan3GB"|gConfigDxeFormSetGuid|0x0|0
  gRaspberryPiTokenSpaceGuid.PcdRamLimitTo3GB|L"RamLimitTo3GB"|gConfigDxeFormSetGuid|0x0|1
  gRaspberryPiTokenSpaceGuid.PcdSystemTableMode|L"SystemTableMode"|gConfigDxeFormSetGuid|0x0|0
DSC
"$HERE/../rpi4-uefi-defaults" "$TMP/RPi4.dsc"
"$HERE/../rpi4-uefi-defaults" "$TMP/RPi4.dsc" # idempotent
[[ $(cut -d'|' -f5 "$TMP/RPi4.dsc" | tr '\n' ' ') == "0 0 2 " ]] || { echo "FAIL: dsc defaults wrong"; exit 1; }
echo '  gRaspberryPiTokenSpaceGuid.PcdSystemTableMode|L"x"|g|0x0|0' >"$TMP/bad.dsc"
if "$HERE/../rpi4-uefi-defaults" "$TMP/bad.dsc" >/dev/null 2>&1; then echo "FAIL: missing pcd accepted"; exit 1; fi
echo "OK"
