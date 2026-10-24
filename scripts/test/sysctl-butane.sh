#!/usr/bin/env bash
# Renders infra/clusters/butane/sysctl.yaml with butane --strict and checks the inotify limits and that the
# file is loaded after Typhoon's max-user-watches.conf (no cluster access).
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SNIPPET="$HERE/../../infra/clusters/butane/sysctl.yaml"

if command -v butane >/dev/null; then butane=(butane)
elif command -v podman >/dev/null; then butane=(podman run --rm -i quay.io/coreos/butane:release)
else echo "SKIP: butane not available"; exit 0; fi

fail() { echo "FAIL: $*"; exit 1; }

ign=$("${butane[@]}" --strict <"$SNIPPET")
path=$(jq -r '.storage.files[] | select(.path | startswith("/etc/sysctl.d/")) | .path' <<<"$ign")
[[ -n $path ]] || fail "no /etc/sysctl.d file"
body=$(jq -r '.storage.files[] | select(.path == "'"$path"'") | .contents.source' <<<"$ign")
data=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.argv[1].split(",", 1)[1]))' "$body")

for key in max_user_instances max_user_watches; do
  value=$(sed -n "s/^fs\.inotify\.$key *= *//p" <<<"$data")
  [[ $value =~ ^[0-9]+$ ]] || fail "$key not set"
done
(($(sed -n 's/^fs\.inotify\.max_user_instances *= *//p' <<<"$data") > 128)) || fail "max_user_instances is not above the default"
[[ $(printf '%s\n' max-user-watches.conf "$(basename "$path")" | sort | tail -1) == "$(basename "$path")" ]] \
  || fail "$(basename "$path") sorts before Typhoon's max-user-watches.conf"
for tf in segv/segv.tf dev/dev.tf; do
  grep -qF 'file("../butane/sysctl.yaml")' "$HERE/../../infra/clusters/$tf" || fail "$tf does not include sysctl.yaml"
done
echo "sysctl-butane: ok"
