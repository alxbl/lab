#!/bin/env zsh

# Exit on first error to make script simpler
set -e

DNS_SERVICES=(dnsmasq@qemu0 systemd-resolved)

# TODO: Check requirements.
# echo "Checking requirements"
# required=(git iptables docker docker-compose jq)

#############################################################################################
echo "[*] Loading environment..."
# https://unix.stackexchange.com/a/115431
SCRIPT_DIR=${0:a:h}
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
source "$REPO_ROOT/.env"

# SETUP
#############################################################################################
if [[ ! -v BOOTSTRAP_NOSECRETS ]]; then
  echo "[*] Mounting secrets drive..."
  if [[ ! -e "/dev/disk/by-partuuid/$LAB_SECRETS_PARTUUID" ]]; then
    echo "ERROR: secrets drive not detected. Make sure it is plugged before running this script"
    exit 1
  fi
  sudo mount "/dev/disk/by-partuuid/$LAB_SECRETS_PARTUUID" /mnt
fi

#############################################################################################
echo "[*] Stopping DNS services..."
DNS_RESTORE=()
for svc in $DNS_SERVICES; do
  # TODO: store state to know whether to restore it.
  echo -n "  $svc... "
  case $(systemctl is-active $svc) in
    active)
      echo "stopping"
      sudo systemctl stop $svc
      DNS_RESTORE+=$svc
      ;;
    *)
      echo "not running"
      ;;
  esac
done

#############################################################################################
# These are specific to my firewall configuration. Your firewall may not have a UDP chain.
echo "[*] Opening firewall ports (TCP:8080, UDP:67,69,4011)"
sudo iptables -A UDP -m udp -p udp --dport 67 -j ACCEPT
sudo iptables -A UDP -m udp -p udp --dport 69 -j ACCEPT
sudo iptables -A UDP -m udp -p udp --dport 4011 -j ACCEPT
sudo iptables -A TCP -m tcp -p tcp --dport 8080 -j ACCEPT

#############################################################################################
if [[ ! -v BOOTSTRAP_QUICK ]]; then
  echo "[*] Generating bootstrapping PKI..."
  "$REPO_ROOT/scripts/bootstrap-pki" >/dev/null
fi

echo "[*] Starting matchbox and DHCP PXE server"
docker-compose -f "$REPO_ROOT/build/bootstrap/docker-compose.yml" up -d

#############################################################################################
# TODO: find the LAN ip to properly template the configuration
# echo "Detecting local ip address..."

#############################################################################################
# Actual bootstap happens in this function.
function do_bootstrap {

  #############################################################################################
  # echo "Creating symlinks for RPI4 nodes"
  # TODO

  #############################################################################################
  echo "[*] Bootstrapping cluster..."
  pushd "$REPO_ROOT/infra/terraform/invoke-typhoon" >/dev/null

  if terraform init; then :; else return 1; fi
  if terraform apply; then :; else return 1; fi

  popd >/dev/null
}

if do_bootstrap; then
  fail=0
else
  fail=1
fi

# CLEANUP
#############################################################################################
echo "[*] Tearing down matchbox and DHCP PXE server"
docker-compose -f "$REPO_ROOT/build/bootstrap/docker-compose.yml" down

#############################################################################################
echo "[*] Restoring DNS services"
for svc in $DNS_RESTORE; do
  sudo systemctl start $svc
  echo "  $svc: started"
done

#############################################################################################
echo "[*] Closing firewall ports"
sudo iptables -D UDP -m udp -p udp --dport 67 -j ACCEPT
sudo iptables -D UDP -m udp -p udp --dport 69 -j ACCEPT
sudo iptables -D UDP -m udp -p udp --dport 4011 -j ACCEPT
sudo iptables -D TCP -m tcp -p tcp --dport 8080 -j ACCEPT

#############################################################################################
if [[ ! -v BOOTSTRAP_NOSECRETS ]]; then
  echo "[*] Unmounting secrets drive"
  sudo umount /mnt
fi

#############################################################################################
if [[ $fail -ne 0 ]]; then
  echo "[!] ERROR: Bootstrapping failed. check output for details."
  exit 1
else
  echo "[+] Done!"
fi
