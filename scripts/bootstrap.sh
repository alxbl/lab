#!/bin/sh
#
# TODO: Check requirements.
# echo "Checking requirements"
# required=(git iptables docker docker-compose jq)

#############################################################################################
echo "Loading environment..."
# https://stackoverflow.com/a/630387
SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$SCRIPT_DIR" && pwd)"
if [[ -z "$SCRIPT_DIR" ]] ; then
  exit 1
fi
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

source "$REPO_ROOT/.env"

#############################################################################################
echo "Mounting secrets drive..."
if [[ ! -e "/dev/disk/by-partuuid/$LAB_SECRETS_PARTUUID" ]]; then
  echo "ERROR: secrets drive not detected. Make sure it is plugged before running this script"
  exit 1
fi

# TODO: What happens if already mounted?
sudo mount "/dev/disk/by-partuuid/$LAB_SECRETS_PARTUUID" /mnt

_ret=$?
if [[ $_ret -ne 0 ]]; then
    echo "ERROR: failed to mount secrets media. (Exit code: $_ret)"
    exit $_ret
fi

#############################################################################################
# These are specific to my firewall configuration. Your firewall may not have a UDP chain.
echo "Opening firewall ports (TCP:8080, UDP:67,69,4011)"
sudo iptables -A UDP -m udp -p udp --dport 67 -j ACCEPT
sudo iptables -A UDP -m udp -p udp --dport 69 -j ACCEPT
sudo iptables -A UDP -m udp -p udp --dport 4011 -j ACCEPT
sudo iptables -A TCP -m tcp -p tcp --dport 8080 -j ACCEPT

#############################################################################################
# TODO: find the LAN ip to properly template the configuration
# echo "Detecting local ip address..."


#############################################################################################
# Remove firewall rules after shutting down
echo "Closing firewall ports"
sudo iptables -D UDP -m udp -p udp --dport 67 -j ACCEPT
sudo iptables -D UDP -m udp -p udp --dport 69 -j ACCEPT
sudo iptables -D UDP -m udp -p udp --dport 4011 -j ACCEPT
sudo iptables -D TCP -m tcp -p tcp --dport 8080 -j ACCEPT

