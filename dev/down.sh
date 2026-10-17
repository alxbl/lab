#!/bin/env zsh
# Stops the dev PXE stack (matchbox + dnsmasq) and restores the host dnsmasq@qemu0 if dev/up.sh stopped it.
# Pass --destroy to also delete the dev VMs.

set -e

SCRIPT_DIR=${0:a:h}
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/lab-dev"
export LIBVIRT_DEFAULT_URI=qemu:///system

if [[ $1 == --destroy ]]; then
  echo "[*] Destroying VMs..."
  sudo "$REPO_ROOT/dev/vm.sh" destroy || true
fi

echo "[*] Stopping matchbox and DHCP PXE server..."
if [[ $(systemctl is-active docker) == active ]]; then
  docker compose -f "$REPO_ROOT/dev/docker-compose.yml" down
fi

echo "[*] Restoring host dnsmasq@qemu0..."
if [[ -f "$STATE_DIR/dnsmasq-was-active" ]]; then
  sudo systemctl start dnsmasq@qemu0
  rm -f "$STATE_DIR/dnsmasq-was-active"
else
  echo "  was not running"
fi

echo "[+] Done!"
