#!/usr/bin/env bash
# USAGE: scripts/install-cilium.sh [--nodes N] <kubeconfig> <cluster>
#
# Installs the Gateway API CRDs and Cilium (Helm, chart version from the system catalog, values from
# infra/system/cilium/values.yaml + values-<cluster>.yaml) on a cluster whose nodes have no CNI yet
# (Typhoon with components.cilium.enable = false). Waits for N nodes (default 1) to register, retries each
# step, and is idempotent: ArgoCD adopts the Helm release afterwards. Does not wait for Cilium to become
# ready: the Hubble certificate job is a post-install hook, which Helm only runs after a --wait would succeed.
# The kubeconfig is required on purpose: .env points $KUBECONFIG at segv.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CILIUM_DIR=$ROOT/infra/system/cilium
NODES=1
RETRIES=${INSTALL_RETRIES:-10}
RETRY_SLEEP=${INSTALL_RETRY_SLEEP:-15}

usage() { sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case $1 in
    --nodes) NODES=${2:?--nodes needs a number}; shift 2 ;;
    -h|--help) usage ;;
    -*) echo "unknown option: $1" >&2; usage ;;
    *) break ;;
  esac
done
[[ $# -eq 2 ]] || usage
KUBECONFIG_FILE=$1 CLUSTER=$2
[[ -r $KUBECONFIG_FILE ]] || { echo "cannot read kubeconfig: $KUBECONFIG_FILE" >&2; exit 1; }
[[ -f $CILIUM_DIR/values-$CLUSTER.yaml ]] || { echo "no values file for cluster '$CLUSTER': $CILIUM_DIR/values-$CLUSTER.yaml" >&2; exit 1; }

VERSION=$(sed -n 's/^ *targetRevision: *\(1\.[0-9.]*\) *$/\1/p' "$ROOT/infra/system/catalog/templates/app-cilium.yaml" | head -1)
[[ -n $VERSION ]] || { echo "could not parse the Cilium chart version from the system catalog" >&2; exit 1; }

# A node may reboot once shortly after install (Zincati, or the ZFS rebase), so the API can disappear briefly.
retry() {
  local n=0
  until "$@"; do
    ((++n >= RETRIES)) && return 1
    echo "  failed, retrying ($n/$RETRIES)..." >&2
    sleep "$RETRY_SLEEP"
  done
}

echo -n "[*] Waiting for $NODES node(s) to register... "
until (($(kubectl --kubeconfig "$KUBECONFIG_FILE" get nodes --no-headers 2>/dev/null | wc -l) >= NODES)); do sleep 5; done
echo "ok"

echo "[*] Installing Gateway API CRDs..."
retry kubectl --kubeconfig "$KUBECONFIG_FILE" apply --server-side --force-conflicts -k "$CILIUM_DIR/gateway-api" >/dev/null

echo "[*] Installing Cilium $VERSION ($CLUSTER)..."
# Isolated repo state so a broken ~/.config/helm does not affect the install.
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/lab-helm
mkdir -p "$STATE"
export HELM_REPOSITORY_CONFIG=$STATE/repositories.yaml HELM_REPOSITORY_CACHE=$STATE/cache
retry helm --kubeconfig "$KUBECONFIG_FILE" upgrade --install cilium cilium --repo https://helm.cilium.io --version "$VERSION" \
  -n kube-system -f "$CILIUM_DIR/values.yaml" -f "$CILIUM_DIR/values-$CLUSTER.yaml" >/dev/null
echo "[+] Cilium $VERSION installed; nodes become Ready once the agents are up."
