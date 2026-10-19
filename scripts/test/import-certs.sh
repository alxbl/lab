#!/usr/bin/env bash
# Exercises scripts/import-certs against a stubbed proton-drive (no Proton Drive access).
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export FAKE_REMOTE=$TMP/remote FAKE_LOG=$TMP/log LAB_SECRETS_REMOTE=/Homelab/_secrets
export PATH="$HERE/stubs:$PATH"
fail() { echo "FAIL: $*" >&2; exit 1; }

# The script writes into <repo>/pki, so run a copy of it from a scratch repo layout.
mkdir -p "$TMP/repo/scripts" "$TMP/repo/pki"
cp "$HERE/../import-certs" "$TMP/repo/scripts/"
P=$FAKE_REMOTE/Homelab/_secrets/segv/pki
mkdir -p "$P/issued"
echo ca >"$P/ca.crt"; echo ca-key >"$P/ca.key"
echo client >"$P/issued/client.crt"; echo client-key >"$P/issued/client.key"

"$TMP/repo/scripts/import-certs" >/dev/null
[[ $(cat "$TMP/repo/pki/ca.crt") == ca ]] || fail "ca.crt not copied"
[[ $(cat "$TMP/repo/pki/client.crt") == client ]] || fail "issued cert not copied"
! ls "$TMP/repo/pki" | grep -q '\.key$' || fail "a private key was copied"

rm -rf "$P"
if "$TMP/repo/scripts/import-certs" 2>/dev/null; then fail "expected failure without remote pki"; fi
echo "import-certs: ok"
