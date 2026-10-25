#!/usr/bin/env bash
# Exercises infra/system/restore-test/restore-test.sh against stubbed kopia and curl (no cluster or repository access).
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$HERE/../../infra/system/restore-test/restore-test.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/bin"

printf 'AZURE_STORAGE_ACCOUNT_ACCESS_KEY=secret\nAZURE_CLOUD_NAME=AzurePublicCloud\n' >"$TMP/cloud"

# FAIL_STEP selects what misbehaves: connect, nosnap, stale, restore, nodb, push.
cat >"$TMP/bin/kopia" <<'STUB'
#!/usr/bin/env bash
[[ -n "${AZURE_STORAGE_KEY:-}" ]] || { echo "key not in environment" >&2; exit 1; }
[[ "$*" != *secret* ]] || { echo "key on command line" >&2; exit 1; }
case "$1 $2" in
  "repository connect") [[ "${FAIL_STEP:-}" == connect ]] && exit 1; exit 0 ;;
  "snapshot list")
    taken=$(date -u -d "${SNAPSHOT_AGE:--2 hours}" '+%Y-%m-%d %H:%M:%S')
    [[ "${FAIL_STEP:-}" == stale ]] && taken=$(date -u -d '-3 days' '+%Y-%m-%d %H:%M:%S')
    echo "default@default:/host_pods/aaa/volumes/kubernetes.io~local-volume/home-assistant"
    echo "  2020-01-01 00:00:00 UTC kOLDHA 1 MB drwxr-xr-x files:1 dirs:1 (latest-1)"
    echo
    if [[ "${FAIL_STEP:-}" != nosnap ]]; then
      echo "default@default:/host_pods/bbb/volumes/kubernetes.io~local-volume/vaultwarden"
      echo "  2020-01-01 00:00:00 UTC kOLDVW 5.2 MB dgrwxrwxr-x files:440 dirs:5 (latest-2)"
      echo "  $taken UTC kNEWVW 5.2 MB dgrwxrwxr-x files:440 dirs:5 (latest-1)"
    fi ;;
  "restore --skip-owners")
    [[ "${FAIL_STEP:-}" == restore || "$3" != kNEWVW ]] && exit 1
    echo "$3 $4" >"$TMP_LOG"
    mkdir -p "$4/attachments"; echo x >"$4/rsa_key.pem"
    if [[ "${FAIL_STEP:-}" == nodb ]]; then echo "not a database" >"$4/db.sqlite3"
    else printf 'SQLite format 3\0rest' >"$4/db.sqlite3"; fi ;;
  *) echo "unexpected: $*" >&2; exit 1 ;;
esac
STUB
cat >"$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
[[ "${FAIL_STEP:-}" == push ]] && exit 22
cp "$METRICS_FILE" "$PAYLOAD"
STUB
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH"

run() {  # run <fail-step>; leaves the pushed payload in $TMP/payload.json
  rm -rf "$TMP/restore" "$TMP/payload.json"; mkdir "$TMP/restore"
  FAIL_STEP="${1:-}" TMP_LOG="$TMP/restore.log" PAYLOAD="$TMP/payload.json" METRICS_FILE="$TMP/metrics.json" \
    REPO_CONTAINER=velero REPO_ACCOUNT=acct REPO_PREFIX=kopia/home/ CREDENTIALS_FILE="$TMP/cloud" \
    VOLUME=vaultwarden NAMESPACE=home RESTORE_DIR="$TMP/restore" REQUIRED_FILE=db.sqlite3 MAX_SNAPSHOT_AGE=129600 \
    OTLP_URL=http://otlp.invalid/v1/metrics KOPIA_PASSWORD=pw "$SCRIPT" >"$TMP/out.log" 2>&1
}

# metric <name>: prints the pushed value, or nothing when the metric is absent.
metric() {
  python3 -I -c '
import json, sys
p = json.load(open(sys.argv[1]))
for m in p["resourceMetrics"][0]["scopeMetrics"][0]["metrics"]:
    if m["name"] == sys.argv[2]:
        dp = m["gauge"]["dataPoints"][0]
        assert {a["key"]: a["value"]["stringValue"] for a in dp["attributes"]} == {"namespace": "home", "volume": "vaultwarden"}
        print(float(dp["asDouble"]))
' "$TMP/payload.json" "$1"
}

run
[[ $(metric restore_test_success) == 1.0 ]] || { echo "FAIL: success not pushed"; cat "$TMP/out.log"; exit 1; }
[[ $(metric restore_test_restored_files) == 2.0 ]] || { echo "FAIL: files not counted"; exit 1; }
[[ -n $(metric restore_test_last_success_timestamp_seconds) ]] || { echo "FAIL: no last-success timestamp"; exit 1; }
age=$(metric restore_test_snapshot_age_seconds)
python3 -I -c 'import sys; a = float(sys.argv[1]); assert 7000 < a < 7400, a' "$age" || { echo "FAIL: snapshot age $age"; exit 1; }
[[ $(cut -d' ' -f1 "$TMP/restore.log") == kNEWVW ]] || { echo "FAIL: newest vaultwarden snapshot not restored"; exit 1; }

for step in connect nosnap stale restore nodb; do
  if run "$step"; then echo "FAIL: $step did not fail the job"; exit 1; fi
  [[ $(metric restore_test_success) == 0.0 ]] || { echo "FAIL: $step did not push success=0"; exit 1; }
  [[ -z $(metric restore_test_last_success_timestamp_seconds) ]] || { echo "FAIL: $step moved the last-success timestamp"; exit 1; }
done

if run push; then echo "FAIL: a failed push was not fatal"; exit 1; fi
echo "ok"
