#!/usr/bin/env bash
# Exercises scripts/firefly-secrets against a stubbed kubectl (no cluster access).
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export FAKE_LOG=$TMP/log FAKE_STATE=$TMP/state
mkdir -p "$FAKE_STATE/home" "$TMP/scripts"
: >"$FAKE_LOG"

# The proxy Secrets are covered by oauth2-proxy-secrets.sh: only check that they are requested.
cp "$HERE/../firefly-secrets" "$TMP/scripts/"
printf '#!/usr/bin/env bash\necho "oauth2-proxy-secrets $*" >>"$FAKE_LOG"\n' >"$TMP/scripts/oauth2-proxy-secrets"
chmod +x "$TMP/scripts/oauth2-proxy-secrets"

cat >"$TMP/kubectl" <<'STUB'
#!/usr/bin/env bash
# Records every call; a Secret "exists" when $FAKE_STATE/<ns>/<name> does.
ns=
[[ ${1:-} == -n ]] && { ns=$2; shift 2; }
echo "kubectl ${ns:+-n $ns }$*" >>"$FAKE_LOG"
case $1 in
  get) [[ -f $FAKE_STATE/$ns/$3 ]] || exit 1 ;;
  create) cat >"$FAKE_STATE/$ns/$4" ;;
esac
STUB
chmod +x "$TMP/kubectl"
export PATH="$TMP:$PATH"

fail() { echo "FAIL: $*" >&2; exit 1; }
S=$FAKE_STATE/home/firefly-secrets

# 1. First run creates firefly-secrets with consistent values and requests the proxy Secrets.
"$TMP/scripts/firefly-secrets"
grep -q 'create secret generic firefly-secrets' "$FAKE_LOG" || fail "secret not created"
grep -q 'oauth2-proxy-secrets firefly home' "$FAKE_LOG" || fail "proxy secrets not requested"
key=$(sed -n 's/^app-key=//p' "$S"); cron=$(sed -n 's/^cron-token=//p' "$S")
[[ ${#key} -eq 32 ]] || fail "APP_KEY is not 32 chars"
[[ ${#cron} -eq 32 && $cron != "$key" ]] || fail "cron token"
[[ $(sed -n 's/^cron-skip-route=//p' "$S") == "^/api/v1/cron/$cron\$" ]] || fail "skip route does not match the token"

# 2. Re-running keeps the Secret.
: >"$FAKE_LOG"
"$TMP/scripts/firefly-secrets"
! grep -q 'create secret' "$FAKE_LOG" || fail "existing secret recreated"
[[ $(sed -n 's/^app-key=//p' "$S") == "$key" ]] || fail "APP_KEY changed"

# 3. No generated value appears on a command line.
! grep -q -F -e "$key" -e "$cron" "$FAKE_LOG" || fail "secret leaked into argv"
echo "firefly-secrets: ok"
