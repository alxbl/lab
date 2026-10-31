#!/usr/bin/env bash
# Exercises scripts/forgejo-secrets against a stubbed kubectl (no cluster access).
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export FAKE_LOG=$TMP/log FAKE_STATE=$TMP/state
mkdir -p "$FAKE_STATE/code" "$FAKE_STATE/keycloak"
: >"$FAKE_LOG"

cat >"$TMP/kubectl" <<'STUB'
#!/usr/bin/env bash
# Records every call; a Secret "exists" when $FAKE_STATE/<ns>/<name> does.
ns=
[[ ${1:-} == -n ]] && { ns=$2; shift 2; }
echo "kubectl ${ns:+-n $ns }$*" >>"$FAKE_LOG"
case $1 in
  get) [[ -f $FAKE_STATE/$ns/$3 ]] || exit 1
       if [[ $3 == forgejo-runner-token ]]; then base64 -w0 <"$FAKE_STATE/$ns/$3"; fi
       if [[ $3 == keycloak-forgejo ]]; then echo '{"data":{"client-secret":"c2VjcmV0"}}'; fi ;;
  create) cat >"$FAKE_STATE/$ns/$4" ;;
  delete) rm -f "$FAKE_STATE/$ns/$3" ;;
  apply) cat >"$FAKE_STATE/applied.json" ;;
  exec) printf '%s\n' "${FAKE_TOKEN-fake-token}" ;;
esac
STUB
chmod +x "$TMP/kubectl"
export PATH="$TMP:$PATH"

fail() { echo "FAIL: $*" >&2; exit 1; }
touch "$FAKE_STATE/keycloak/keycloak-forgejo"

# 1. First run creates the admin Secret and applies the derived OAuth Secret; no runner token without the flag.
"$HERE/../forgejo-secrets"
grep -q 'create secret generic forgejo-admin' "$FAKE_LOG" || fail "admin secret not created"
! grep -q 'forgejo-runner-token' "$FAKE_LOG" || fail "runner token created without --runner-token"
python3 -I - "$FAKE_STATE/applied.json" <<'PY' || fail "oauth secret content"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["metadata"]["name"] == "forgejo-oauth" and d["metadata"]["namespace"] == "code"
assert d["stringData"] == {"key": "forgejo", "secret": "secret"}
PY

# 2. Re-running keeps the existing admin Secret.
: >"$FAKE_LOG"
"$HERE/../forgejo-secrets"
! grep -q 'create secret generic forgejo-admin' "$FAKE_LOG" || fail "existing admin secret recreated"

# 3. --runner-token creates the token once.
: >"$FAKE_LOG"
"$HERE/../forgejo-secrets" --runner-token
grep -q 'create secret generic forgejo-runner-token' "$FAKE_LOG" || fail "runner token not created"
: >"$FAKE_LOG"
"$HERE/../forgejo-secrets" --runner-token
! grep -q 'exec' "$FAKE_LOG" || fail "runner token regenerated"

# 3b. An empty Secret counts as missing and is replaced.
: >"$FAKE_STATE/code/forgejo-runner-token"
: >"$FAKE_LOG"
"$HERE/../forgejo-secrets" --runner-token
grep -q 'delete secret forgejo-runner-token' "$FAKE_LOG" || fail "empty runner token not replaced"
grep -q 'create secret generic forgejo-runner-token' "$FAKE_LOG" || fail "runner token not recreated"
[[ -s $FAKE_STATE/code/forgejo-runner-token ]] || fail "recreated runner token is empty"

# 3c. An empty answer from Forgejo fails and creates nothing.
rm -f "$FAKE_STATE/code/forgejo-runner-token"
: >"$FAKE_LOG"
if FAKE_TOKEN= "$HERE/../forgejo-secrets" --runner-token 2>/dev/null; then fail "empty token accepted"; fi
! grep -q 'create secret generic forgejo-runner-token' "$FAKE_LOG" || fail "empty token stored"

# 4. No generated value appears on a command line.
! grep -q 'fake-token' "$FAKE_LOG" || fail "token leaked into argv"
echo "forgejo-secrets: ok"
