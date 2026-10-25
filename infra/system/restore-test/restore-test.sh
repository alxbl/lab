#!/bin/sh
# Restores the newest kopia snapshot of one Velero-backed volume into RESTORE_DIR (a tmpfs), checks it, and pushes the
# result to an OTLP/HTTP metrics endpoint. Exits non-zero, after pushing success=0, when any step fails.
#
# Environment: REPO_CONTAINER REPO_ACCOUNT REPO_PREFIX CREDENTIALS_FILE (dotenv with AZURE_STORAGE_ACCOUNT_ACCESS_KEY)
# VOLUME (PV name; the last element of the snapshot source path) NAMESPACE (label only) RESTORE_DIR REQUIRED_FILE
# (SQLite database that must be present) MAX_SNAPSHOT_AGE (seconds) OTLP_URL. KOPIA_PASSWORD comes from the pod.
# METRICS_FILE is scratch space for the payload.
set -u

METRICS_FILE="${METRICS_FILE:-/tmp/metrics.json}"
success=0
duration=0
snapshot_age=0
files=0
bytes=0

now() { date +%s.%N; }

fail() {
  echo "restore-test: $*" >&2
  exit 1
}

push() {
  ts="$(date +%s)000000000"
  attrs="[{\"key\":\"namespace\",\"value\":{\"stringValue\":\"$NAMESPACE\"}},{\"key\":\"volume\",\"value\":{\"stringValue\":\"$VOLUME\"}}]"
  gauge() { printf '{"name":"%s","unit":"%s","gauge":{"dataPoints":[{"asDouble":%s,"timeUnixNano":"%s","attributes":%s}]}}' "$1" "$2" "$3" "$ts" "$attrs"; }
  metrics="$(gauge restore_test_success '' "$success")"
  metrics="$metrics,$(gauge restore_test_duration_seconds s "$duration")"
  metrics="$metrics,$(gauge restore_test_snapshot_age_seconds s "$snapshot_age")"
  metrics="$metrics,$(gauge restore_test_restored_files '' "$files")"
  metrics="$metrics,$(gauge restore_test_restored_bytes By "$bytes")"
  # Only a success moves this forward, so the last good run stays visible after a failure.
  [ "$success" = 1 ] && metrics="$metrics,$(gauge restore_test_last_success_timestamp_seconds s "$(date +%s)")"
  printf '{"resourceMetrics":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"restore-test"}}]},"scopeMetrics":[{"scope":{"name":"restore-test"},"metrics":[%s]}]}]}' "$metrics" >"$METRICS_FILE"
  curl -fsS --max-time 30 -H 'Content-Type: application/json' --data-binary @"$METRICS_FILE" "$OTLP_URL" >/dev/null
}

finish() {
  rc=$?
  push || { echo "restore-test: pushing metrics failed" >&2; [ "$rc" = 0 ] && rc=1; }
  exit "$rc"
}
trap finish EXIT

# The key is read from the mounted Secret into the environment, never onto a command line.
AZURE_STORAGE_KEY="$(sed -n 's/^AZURE_STORAGE_ACCOUNT_ACCESS_KEY=//p' "$CREDENTIALS_FILE")"
export AZURE_STORAGE_KEY
[ -n "$AZURE_STORAGE_KEY" ] || fail "no storage key in $CREDENTIALS_FILE"

kopia repository connect azure --readonly --container "$REPO_CONTAINER" --storage-account "$REPO_ACCOUNT" \
  --prefix "$REPO_PREFIX" --override-hostname=restore-test --override-username=restore-test >/dev/null ||
  fail "cannot connect to the repository"

# Velero's source paths embed the pod UID, which changes; the PV name at the end does not.
snapshot="$(kopia snapshot list --all | awk -v vol="$VOLUME" '
  /^default@/ { keep = ($0 ~ ("/" vol "$")); next }
  keep && /^  [0-9]/ { id = $4; stamp = $1 " " $2 }
  END { if (id != "") print id, stamp }')"
[ -n "$snapshot" ] || fail "no snapshot for volume $VOLUME"
id="${snapshot%% *}"
taken="$(date -u -d "${snapshot#* }" +%s)" || fail "cannot parse snapshot time '${snapshot#* }'"
snapshot_age=$(($(date +%s) - taken))

start="$(now)"
# --skip-owners: the job drops all capabilities, and ownership is not what is being tested.
kopia restore --skip-owners "$id" "$RESTORE_DIR" >/dev/null || fail "restore of $id failed"
duration="$(awk -v s="$start" -v e="$(now)" 'BEGIN { printf "%.3f", e - s }')"

files="$(find "$RESTORE_DIR" -type f | wc -l)"
bytes="$(du -sb "$RESTORE_DIR" | cut -f1)"
[ "$files" -gt 0 ] || fail "snapshot $id restored no files"
[ "$(head -c 15 "$RESTORE_DIR/$REQUIRED_FILE" 2>/dev/null)" = "SQLite format 3" ] || fail "$REQUIRED_FILE is missing or not a SQLite database"
[ "$snapshot_age" -le "$MAX_SNAPSHOT_AGE" ] || fail "newest snapshot $id is ${snapshot_age}s old"

success=1
echo "restore-test: restored $id ($files files, $bytes bytes) in ${duration}s"
