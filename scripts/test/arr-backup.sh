#!/usr/bin/env bash
# Exercises scripts/arr-backup against a stubbed kubectl (no cluster access).
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/bin"

sqlite3 "$TMP/app.db" 'create table t(x)'
python3 -I -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1], "w").write(sys.argv[2], "app.db")' "$TMP/backup.zip" "$TMP/app.db"

# FAIL_STEP selects which kubectl call misbehaves.
cat >"$TMP/bin/kubectl" <<STUB
#!/usr/bin/env bash
case "\$1" in
  auth) [[ "\${FAIL_STEP:-}" == auth ]] && exit 1; echo yes ;;
  get) echo aquisition-pod ;;
  exec)
    if [[ "\$*" == *"rm -v"* ]]; then echo "\$*" >>"$TMP/prune.log"
    elif [[ "\$*" == *" cat "* ]]; then cat "$TMP/backup.zip"
    else [[ "\${FAIL_STEP:-}" == backup ]] && { echo "backup command failed" >&2; exit 1; }
         echo /media/.config/X/Backups/manual/backup.zip; fi ;;
esac
STUB
chmod +x "$TMP/bin/kubectl"
export PATH="$TMP/bin:$PATH"

"$HERE/../arr-backup" "$TMP/out" >/dev/null
[[ $(ls "$TMP/out" | wc -l) -eq 3 ]] || { echo "FAIL: expected 3 zips"; exit 1; }

for step in auth backup; do
  if FAIL_STEP=$step "$HERE/../arr-backup" "$TMP/out2" >/dev/null 2>&1; then
    echo "FAIL: $step failure was not fatal"; exit 1
  fi
done
"$HERE/../arr-backup" --keep 2 "$TMP/out3" >/dev/null
[[ $(wc -l <"$TMP/prune.log") -eq 3 ]] || { echo "FAIL: --keep did not prune each app"; exit 1; }
[[ $(grep -c ' 2$' "$TMP/prune.log") -eq 3 ]] || { echo "FAIL: --keep N not passed"; exit 1; }
if "$HERE/../arr-backup" --keep 0 "$TMP/out4" >/dev/null 2>&1; then
  echo "FAIL: --keep 0 accepted"; exit 1
fi
echo "ok"

# The API lives under the app's configured UrlBase (Sonarr redirects bare /api requests, which curl does not follow for POST).
mkdir -p "$TMP/cfg/Sonarr" "$TMP/cfg/Radarr" "$TMP/curlbin"
printf '<Config><ApiKey>k</ApiKey><Port>8989</Port><UrlBase>sonarr</UrlBase></Config>' >"$TMP/cfg/Sonarr/config.xml"
printf '<Config><ApiKey>k</ApiKey><Port>7878</Port><UrlBase></UrlBase></Config>' >"$TMP/cfg/Radarr/config.xml"
mkdir -p "$TMP/cfg/Sonarr/Backups/manual" "$TMP/cfg/Radarr/Backups/manual"
touch "$TMP/cfg/Sonarr/Backups/manual/b.zip" "$TMP/cfg/Radarr/Backups/manual/b.zip"
cat >"$TMP/curlbin/curl" <<STUB
#!/usr/bin/env bash
echo "\${@: -1}" >>"$TMP/urls.log"
case "\${@: -1}" in
  */command) echo '{"id": 7}' ;;
  */command/7) echo '{"status": "completed"}' ;;
esac
STUB
chmod +x "$TMP/curlbin/curl"
sed -n "/^REMOTE='/,/^'\$/p" "$HERE/../arr-backup" | sed '1s/^REMOTE=.//;$d' >"$TMP/remote.sh"
for entry in Sonarr:v3:8989:/sonarr Radarr:v3:7878:""; do
  IFS=: read -r app ver port ub <<<"$entry"
  PATH="$TMP/curlbin:$PATH" ARR_CONFIG_ROOT="$TMP/cfg" sh "$TMP/remote.sh" "$app" "$ver" >/dev/null
  grep -qx "http://localhost:$port$ub/api/$ver/command" "$TMP/urls.log" || { echo "FAIL: $app did not use its UrlBase (got: $(cat "$TMP/urls.log" | tr '\n' ' '))"; exit 1; }
done
echo "arr-backup: ok"
