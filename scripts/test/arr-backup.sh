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
    if [[ "\$*" == *" cat "* ]]; then cat "$TMP/backup.zip"
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
echo "ok"
