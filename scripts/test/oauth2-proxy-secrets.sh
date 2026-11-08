#!/usr/bin/env bash
# Exercises scripts/oauth2-proxy-secrets against a stubbed kubectl (no cluster access).
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export FAKE_LOG=$TMP/log FAKE_STATE=$TMP/state
mkdir -p "$FAKE_STATE/keycloak" "$FAKE_STATE/home"
: >"$FAKE_LOG"

cat >"$TMP/kubectl" <<'STUB'
#!/usr/bin/env bash
# Records every call; a Secret "exists" when $FAKE_STATE/<ns>/<name> does. Applied Secrets are stored as JSON.
ns=
[[ ${1:-} == -n ]] && { ns=$2; shift 2; }
echo "kubectl ${ns:+-n $ns }$*" >>"$FAKE_LOG"
case $1 in
  get) f=$FAKE_STATE/$ns/$3; [[ -f $f ]] || exit 1
       case $* in
         *jsonpath*) python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["data"]["cookie-secret"], end="")' "$f" ;;
         *) cat "$f" ;;
       esac ;;
  create) printf '{"data":{"client-secret":"%s"}}' "$(base64 -w0 </dev/stdin)" >"$FAKE_STATE/$ns/$4" ;;
  apply) cat >"$FAKE_STATE/applied.json"
         python3 -I - "$FAKE_STATE" <<'PY'
import base64, json, sys
d = json.load(open(sys.argv[1] + "/applied.json"))
data = {k: base64.b64encode(v.encode()).decode() for k, v in d["stringData"].items()}
json.dump({"data": data}, open(f'{sys.argv[1]}/{d["metadata"]["namespace"]}/{d["metadata"]["name"]}', "w"))
PY
         ;;
esac
STUB
chmod +x "$TMP/kubectl"
export PATH="$TMP:$PATH"

fail() { echo "FAIL: $*" >&2; exit 1; }
applied() { python3 -I - "$FAKE_STATE/applied.json" "$1" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["stringData"][sys.argv[2]], end="")
PY
}

# 1. First run creates the Keycloak client secret, labels it, and applies the derived Secret.
"$HERE/../oauth2-proxy-secrets" demo home
grep -q 'create secret generic keycloak-demo' "$FAKE_LOG" || fail "keycloak secret not created"
grep -q 'label secret keycloak-demo operator.keycloak.org/kind=KeycloakOIDCClient' "$FAKE_LOG" || fail "client secret not labelled"
python3 -I - "$FAKE_STATE/applied.json" "$FAKE_STATE/keycloak/keycloak-demo" <<'PY' || fail "derived secret content"
import base64, json, sys
d = json.load(open(sys.argv[1]))
src = base64.b64decode(json.load(open(sys.argv[2]))["data"]["client-secret"]).decode()
assert d["metadata"] == {"name": "demo-oauth2-proxy", "namespace": "home"}
s = d["stringData"]
assert s["client-id"] == "demo" and s["client-secret"] == src and len(src) == 48, s
assert len(base64.urlsafe_b64decode(s["cookie-secret"])) == 32
PY
cookie=$(applied cookie-secret)

# 2. Re-running keeps the Keycloak secret and the cookie secret.
: >"$FAKE_LOG"
"$HERE/../oauth2-proxy-secrets" demo home
! grep -q 'create secret' "$FAKE_LOG" || fail "existing keycloak secret recreated"
[[ $(applied cookie-secret) == "$cookie" ]] || fail "cookie secret regenerated"

# 3. Bad arguments are rejected before any kubectl call.
: >"$FAKE_LOG"
if "$HERE/../oauth2-proxy-secrets" 'x y' home 2>/dev/null; then fail "bad app accepted"; fi
if "$HERE/../oauth2-proxy-secrets" demo 2>/dev/null; then fail "missing namespace accepted"; fi
[[ ! -s $FAKE_LOG ]] || fail "kubectl called on bad arguments"

# 4. No generated value appears on a command line.
! grep -q -F "$cookie" "$FAKE_LOG" || fail "cookie secret leaked into argv"
echo "oauth2-proxy-secrets: ok"
