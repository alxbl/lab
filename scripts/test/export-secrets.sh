#!/usr/bin/env bash
# Exercises scripts/export-secrets against stubbed kubectl and proton-drive (no cluster or Proton Drive access).
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export FAKE_REMOTE=$TMP/remote FAKE_CLUSTER=$TMP/cluster FAKE_LOG=$TMP/log
export LAB_SECRETS_REMOTE=/Homelab/_secrets SECRETS_LIST=$TMP/list
export PATH="$HERE/stubs:$PATH"
mkdir -p "$FAKE_REMOTE/Homelab" "$FAKE_CLUSTER/cert-manager" "$FAKE_CLUSTER/media"
: >"$FAKE_LOG"
echo apiVersion=v1 >"$TMP/kubeconfig"

cat >"$FAKE_CLUSTER/cert-manager/cloudflare-api-secret.json" <<'JSON'
{"apiVersion":"v1","kind":"Secret","type":"Opaque","data":{"api-token":"c2VjcmV0"},
 "metadata":{"name":"cloudflare-api-secret","namespace":"cert-manager","uid":"abc","resourceVersion":"42",
   "creationTimestamp":"2024-01-01T00:00:00Z","managedFields":[{"manager":"kubectl"}],
   "annotations":{"kubectl.kubernetes.io/last-applied-configuration":"{}"}}}
JSON
cat >"$TMP/list" <<'LIST'
# comment
cert-manager/cloudflare-api-secret
media/not-there optional
LIST

fail() { echo "FAIL: $*" >&2; exit 1; }

# 1. Exports, scrubs cluster metadata, uploads under <cluster>/manifests, tolerates a missing optional secret.
"$HERE/../export-secrets" "$TMP/kubeconfig" >"$TMP/out"
F=$FAKE_REMOTE/Homelab/_secrets/segv/manifests/cert-manager/cloudflare-api-secret.yaml
[[ -f $F ]] || fail "secret not uploaded to the expected path"
for field in uid resourceVersion creationTimestamp managedFields last-applied; do
  ! grep -q "$field" "$F" || fail "$field was not stripped"
done
grep -q 'api-token: c2VjcmV0' "$F" || fail "data lost"
grep -q 'skip (optional, not found): media/not-there' "$TMP/out" || fail "optional skip not reported"
! grep -q c2VjcmV0 "$TMP/out" || fail "secret value leaked to stdout"

# 2. --cluster selects the remote folder.
"$HERE/../export-secrets" --cluster other "$TMP/kubeconfig" >/dev/null
[[ -f $FAKE_REMOTE/Homelab/_secrets/other/manifests/cert-manager/cloudflare-api-secret.yaml ]] || fail "--cluster ignored"

# 3. A missing required secret aborts before anything is uploaded.
rm -rf "$FAKE_REMOTE/Homelab/_secrets"; : >"$FAKE_LOG"
echo "media/required-missing" >>"$TMP/list"
if "$HERE/../export-secrets" "$TMP/kubeconfig" 2>"$TMP/err"; then fail "expected failure for a missing required secret"; fi
grep -q 'missing required secret: media/required-missing' "$TMP/err" || fail "missing secret not reported"
! grep -q upload "$FAKE_LOG" || fail "upload happened despite a missing required secret"

# 4. The kubeconfig argument is required.
if "$HERE/../export-secrets" 2>/dev/null; then fail "expected usage error without kubeconfig"; fi
echo "export-secrets: ok"
