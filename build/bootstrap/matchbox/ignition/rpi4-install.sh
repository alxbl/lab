#!/usr/bin/bash
# Installs Fedora CoreOS on the first USB disk and copies the Raspberry Pi 4
# firmware onto its ESP so the Pi can boot from the disk without the network.
set -euo pipefail

MATCHBOX=http://matchbox.lan:8080
DEV=/dev/sda
FIRMWARE=(
  start4.elf
  fixup4.dat
  bcm2711-rpi-4-b.dtb
  config.txt
  RPI_EFI.fd
  overlays/disable-bt.dtbo
  overlays/upstream-pi4.dtbo
)

# coreos-installer refuses plain-HTTP --ignition-url without a hash.
ign=$(mktemp)
curl -fsS -o "$ign" "$MATCHBOX/assets/node-arm64.ign"
# vc4 retries probing forever on this kernel, which keeps udev from settling.
coreos-installer install "$DEV" --ignition-file "$ign" --append-karg modprobe.blacklist=vc4
udevadm settle

esp=$(mktemp -d)
mount /dev/disk/by-partlabel/EFI-SYSTEM "$esp"
for f in "${FIRMWARE[@]}"; do
  curl -fsS --create-dirs -o "$esp/$f" "$MATCHBOX/assets/rpi4/$f"
done
umount "$esp"
