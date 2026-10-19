#!/usr/bin/env bash
# Exercises scripts/import-secrets against stubbed kubectl and proton-drive (no cluster or Proton Drive access).
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export FAKE_REMOTE=$TMP/remote FAKE_CLUSTER=$TMP/cluster FAKE_LOG=$TMP/log
export LAB_SECRETS_REMOTE=/Homelab/_secrets
export PATH="$HERE/stubs:$PATH"
M=$FAKE_REMOTE/Homelab/_secrets/segv/manifests
mkdir -p "$M/media" "$M/system" "$FAKE_CLUSTER/system"
echo "kind: Secret" >"$M/media/smbd-credentials.yaml"
echo "kind: Secret" >"$M/system/velero-repo-credentials.yaml"
echo apiVersion=v1 >"$TMP/kubeconfig"

fail() { echo "FAIL: $*" >&2; exit 1; }
reset() { : >"$FAKE_LOG"; rm -rf "$FAKE_CLUSTER/media"; }

# 1. Creates only the missing namespaces, then applies every secret.
reset
"$HERE/../import-secrets" "$TMP/kubeconfig" >"$TMP/out"
grep -q 'kubectl create namespace media' "$FAKE_LOG" || fail "missing namespace not created"
! grep -q 'create namespace system' "$FAKE_LOG" || fail "existing namespace was recreated"
[[ $(grep -c 'kubectl .*apply' "$FAKE_LOG") -eq 2 ]] || fail "expected 2 applies"
grep -q 'target: https://fake.example:6443' "$TMP/out" || fail "target cluster not printed"

# 2. Namespace arguments restrict the import.
reset
"$HERE/../import-secrets" "$TMP/kubeconfig" system >"$TMP/out"
[[ $(grep -c 'kubectl .*apply' "$FAKE_LOG") -eq 1 ]] || fail "namespace filter ignored"
grep -q 'applied system/velero-repo-credentials' "$TMP/out" || fail "wrong secret applied"

# 3. --dry-run creates nothing and uses server-side validation only where the namespace exists.
reset
"$HERE/../import-secrets" --dry-run "$TMP/kubeconfig" >"$TMP/out"
! grep -q 'create namespace' "$FAKE_LOG" || fail "dry run created a namespace"
grep -q -- '--dry-run=server.*velero-repo-credentials' "$FAKE_LOG" || fail "existing namespace should validate server side"
grep -q -- '--dry-run=client.*smbd-credentials' "$FAKE_LOG" || fail "missing namespace should validate client side"
grep -q 'would apply media/smbd-credentials' "$TMP/out" || fail "dry run output"

# 4. Missing remote manifests and a missing kubeconfig both fail.
rm -rf "$FAKE_REMOTE/Homelab/_secrets/segv"
if "$HERE/../import-secrets" "$TMP/kubeconfig" 2>/dev/null; then fail "expected failure without remote manifests"; fi
if "$HERE/../import-secrets" 2>/dev/null; then fail "expected usage error without kubeconfig"; fi
echo "import-secrets: ok"
