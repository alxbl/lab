#!/usr/bin/env bash
# Exercises scripts/paperless-secrets against a stubbed kubectl (no cluster access).
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export FAKE_LOG=$TMP/log FAKE_STATE=$TMP/state
mkdir -p "$FAKE_STATE/media" "$FAKE_STATE/keycloak"
: >"$FAKE_LOG"

cat >"$TMP/kubectl" <<'STUB'
#!/usr/bin/env bash
# Records every call; `get secret` prints the stored JSON, `apply` stores the Secret it is given.
ns=
[[ ${1:-} == -n ]] && { ns=$2; shift 2; }
echo "kubectl ${ns:+-n $ns }$*" >>"$FAKE_LOG"
case $1 in
  get) [[ -f $FAKE_STATE/$ns/$3 ]] || exit 1; cat "$FAKE_STATE/$ns/$3" ;;
  apply) cat >"$FAKE_STATE/in.json"; [[ -s $FAKE_STATE/in.json ]] || exit 1  # kubectl rejects empty input
         mv "$FAKE_STATE/in.json" "$FAKE_STATE/applied.json"
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
field() { python3 -I - "$FAKE_STATE/applied.json" "$1" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["stringData"][sys.argv[2]], end="")
PY
}

# 1. Without the Keycloak client secret it fails and applies nothing.
if "$HERE/../paperless-secrets" 2>/dev/null; then fail "ran without keycloak-paperless"; fi
[[ ! -e $FAKE_STATE/applied.json ]] || fail "applied without keycloak-paperless"

# 2. With it, the providers JSON carries the client secret and the generated values exist.
printf '{"data":{"client-secret":"%s"}}' "$(printf s3cret | base64 -w0)" >"$FAKE_STATE/keycloak/keycloak-paperless"
"$HERE/../paperless-secrets"
python3 -I - "$FAKE_STATE/applied.json" <<'PY' || fail "secret content"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["metadata"] == {"name": "paperless-secrets", "namespace": "media"}
s = d["stringData"]
assert len(s["PAPERLESS_SECRET_KEY"]) >= 64 and len(s["PAPERLESS_ADMIN_PASSWORD"]) >= 24
assert s["PAPERLESS_ADMIN_USER"] == "paperless-admin"
app = json.loads(s["PAPERLESS_SOCIALACCOUNT_PROVIDERS"])["openid_connect"]["APPS"][0]
assert app["provider_id"] == "keycloak" and app["client_id"] == "paperless" and app["secret"] == "s3cret"
assert app["settings"]["server_url"].endswith("/realms/segv/.well-known/openid-configuration")
PY
key=$(field PAPERLESS_SECRET_KEY); pass=$(field PAPERLESS_ADMIN_PASSWORD)

# 3. Re-running keeps the generated values and refreshes the client secret.
printf '{"data":{"client-secret":"%s"}}' "$(printf rotated | base64 -w0)" >"$FAKE_STATE/keycloak/keycloak-paperless"
"$HERE/../paperless-secrets"
[[ $(field PAPERLESS_SECRET_KEY) == "$key" ]] || fail "secret key regenerated"
[[ $(field PAPERLESS_ADMIN_PASSWORD) == "$pass" ]] || fail "admin password regenerated"
field PAPERLESS_SOCIALACCOUNT_PROVIDERS | grep -q rotated || fail "client secret not refreshed"

# 4. No generated value appears on a command line.
! grep -q -F -e "$key" -e "$pass" -e s3cret "$FAKE_LOG" || fail "secret leaked into argv"
echo "paperless-secrets: ok"
