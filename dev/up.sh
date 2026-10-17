#!/bin/env zsh
# Clean start of the dev KVM cluster (node1/node2 on qemu0, see DEVELOPMENT.md).
# Idempotent: every run wipes the VMs and terraform state and rebuilds the cluster.
# Leaves matchbox and dnsmasq running so rebooting nodes can still PXE. Use dev/down.sh to stop them.
#
# Env: READY_TIMEOUT (seconds to wait for Ready nodes, default 900)

set -e

READY_TIMEOUT=${READY_TIMEOUT:-900}
NODES=(node1 node2)
NODE_MACS=(52:54:00:a1:9c:ae 52:54:00:b2:2f:86)
BRIDGE=qemu0
BRIDGE_IP=10.2.0.1

echo "[*] Loading environment..."
SCRIPT_DIR=${0:a:h}
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
source "$REPO_ROOT/.env"
# .env points KUBECONFIG at the real cluster. Never let it leak into dev.
unset KUBECONFIG

CLUSTER_DIR="$REPO_ROOT/infra/clusters/dev"
KUBECONF="$CLUSTER_DIR/dev.conf"
COMPOSE=(docker compose -f "$REPO_ROOT/dev/docker-compose.yml")
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/lab-dev"
mkdir -p "$STATE_DIR"

#############################################################################################
echo "[*] Checking requirements..."
missing=()
for t in terraform kubectl docker virsh virt-install jq openssl curl sudo; do
  (( $+commands[$t] )) || missing+=$t
done
if (( $#missing )); then
  echo "[!] ERROR: missing tools: $missing"
  exit 1
fi
sudo -n true 2>/dev/null || { echo "[!] ERROR: passwordless sudo required"; exit 1; }
export LIBVIRT_DEFAULT_URI=qemu:///system

#############################################################################################
echo "[*] Ensuring docker is running..."
if [[ $(systemctl is-active docker) != active ]]; then
  sudo systemctl start docker
fi

#############################################################################################
echo "[*] Stopping host dnsmasq@$BRIDGE..."
if [[ $(systemctl is-active dnsmasq@$BRIDGE) == active ]]; then
  # Remembered across runs so down.sh can restore it.
  touch "$STATE_DIR/dnsmasq-was-active"
  sudo systemctl stop dnsmasq@$BRIDGE
else
  echo "  not running"
fi

#############################################################################################
if [[ ! -f "$REPO_ROOT/pki/server.crt" || ! -f "$REPO_ROOT/pki/client.crt" || ! -f "$REPO_ROOT/pki/client.key" ]]; then
  echo "[*] Generating bootstrapping PKI..."
  "$REPO_ROOT/scripts/bootstrap-pki" >/dev/null
else
  echo "[*] Bootstrapping PKI present, skipping"
fi

#############################################################################################
OS_VERSION=$(sed -n 's/^ *os_version *= *"\(.*\)".*/\1/p' "$CLUSTER_DIR/dev.tf")
OS_STREAM=$(sed -n 's/^ *os_stream *= *"\(.*\)".*/\1/p' "$CLUSTER_DIR/dev.tf")
ASSETS="$REPO_ROOT/build/bootstrap/matchbox/assets/fedora-coreos"
if [[ -z $OS_VERSION ]]; then
  echo "[!] ERROR: could not parse os_version from dev.tf"
  exit 1
fi
if [[ ! -e "$ASSETS/fedora-coreos-$OS_VERSION-live-kernel.x86_64" ]]; then
  echo "[*] Downloading Fedora CoreOS $OS_VERSION..."
  "$REPO_ROOT/scripts/get-fedora-coreos" ${OS_STREAM:-stable} $OS_VERSION
else
  echo "[*] Fedora CoreOS $OS_VERSION present, skipping"
fi

#############################################################################################
echo "[*] Starting matchbox and DHCP PXE server..."
$COMPOSE up -d
echo -n "  waiting for matchbox... "
for i in {1..30}; do
  curl -sf -o /dev/null http://127.0.0.1:8080/ && break
  sleep 1
done
echo "ok"

#############################################################################################
echo "[*] Wiping stale terraform state..."
pushd "$CLUSTER_DIR" >/dev/null
terraform init -input=false >/dev/null
if [[ -f terraform.tfstate ]]; then
  terraform destroy -auto-approve -input=false >/dev/null || {
    echo "  destroy failed, removing state"
    rm -f terraform.tfstate terraform.tfstate.backup
  }
fi
rm -f terraform.tfstate terraform.tfstate.backup dev.conf
popd >/dev/null

#############################################################################################
echo "[*] Recreating VMs..."
sudo "$REPO_ROOT/dev/vm.sh" destroy >/dev/null 2>&1 || true
sudo "$REPO_ROOT/dev/vm.sh" create >/dev/null

# Nodes cache old host keys; fresh installs generate new ones.
for ip in 10.2.0.101 10.2.0.102; do ssh-keygen -R $ip >/dev/null 2>&1 || true; done

#############################################################################################
# qemu0 has no carrier (and no address) until a VM attaches, so dnsmasq cannot serve DHCP/TFTP
# until then. Once the address shows up, restart dnsmasq so it binds, and reset the VMs once
# matchbox has a profile for them (terraform creates it below) so they restart their PXE boot.
function pxe_kick {
  for i in {1..120}; do
    ip -4 addr show dev $BRIDGE 2>/dev/null | grep -q "inet $BRIDGE_IP/" && break
    sleep 1
  done
  $COMPOSE restart proxydhcp >/dev/null 2>&1
  for mac in $NODE_MACS; do
    for i in {1..300}; do
      curl -sf -o /dev/null "http://127.0.0.1:8080/ipxe?mac=$mac" && break
      sleep 1
    done
  done
  for n in $NODES; do virsh reset $n >/dev/null 2>&1; done
}

echo "[*] Bootstrapping cluster (terraform apply)..."
pxe_kick &
KICK_PID=$!
trap 'kill $KICK_PID 2>/dev/null' EXIT
pushd "$CLUSTER_DIR" >/dev/null
terraform apply -auto-approve -input=false
popd >/dev/null
wait $KICK_PID 2>/dev/null || true

#############################################################################################
echo "[*] Waiting for nodes to be Ready (timeout ${READY_TIMEOUT}s)..."
deadline=$(( SECONDS + READY_TIMEOUT ))
while true; do
  ready=$(kubectl --kubeconfig "$KUBECONF" get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l)
  (( ready >= $#NODES )) && break
  if (( SECONDS > deadline )); then
    kubectl --kubeconfig "$KUBECONF" get nodes 2>&1 || true
    echo "[!] ERROR: timed out waiting for nodes to be Ready"
    exit 1
  fi
  sleep 10
done
kubectl --kubeconfig "$KUBECONF" get nodes

echo "[+] Done! Use: kubectl --kubeconfig $KUBECONF ..."
