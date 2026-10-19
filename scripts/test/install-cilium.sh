#!/usr/bin/env bash
# Exercises scripts/install-cilium.sh against stubbed kubectl and helm (no cluster access).
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/bin"
export XDG_STATE_HOME=$TMP/state INSTALL_RETRY_SLEEP=0 LOG=$TMP/log
echo apiVersion=v1 >"$TMP/kubeconfig"

# FAIL_HELM_ONCE=1 makes the first helm call fail; NODES_READY is what `get nodes` reports.
cat >"$TMP/bin/kubectl" <<'STUB'
#!/usr/bin/env bash
case "$3" in
  get) for i in $(seq "${NODES_READY:-1}"); do echo "node$i Ready"; done ;;
  apply) echo "kubectl $*" >>"$LOG" ;;
esac
STUB
cat >"$TMP/bin/helm" <<'STUB'
#!/usr/bin/env bash
echo "helm $*" >>"$LOG"
if [[ -n ${FAIL_HELM_ONCE:-} && ! -e $LOG.failed ]]; then touch "$LOG.failed"; exit 1; fi
STUB
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH"
fail() { echo "FAIL: $*" >&2; exit 1; }

VERSION=$(sed -n 's/^ *targetRevision: *\(1\.[0-9.]*\) *$/\1/p' "$ROOT/infra/system/catalog/templates/app-cilium.yaml" | head -1)

# 1. Installs the CRDs, then the chart at the catalog version with the shared and per-cluster values.
: >"$LOG"; NODES_READY=2 "$ROOT/scripts/install-cilium.sh" --nodes 2 "$TMP/kubeconfig" dev >/dev/null
grep -q -- 'apply --server-side --force-conflicts -k .*/infra/system/cilium/gateway-api' "$LOG" || fail "gateway API CRDs not applied"
grep -q -- "--version $VERSION" "$LOG" || fail "chart version not taken from the catalog ($VERSION)"
grep -q -- 'infra/system/cilium/values.yaml -f .*/values-dev.yaml' "$LOG" || fail "values files"
[[ $(grep -c '^kubectl' "$LOG") -eq 1 && $(grep -c '^helm' "$LOG") -eq 1 ]] || fail "unexpected call count"

# 2. A failing helm call is retried.
: >"$LOG"; rm -f "$LOG.failed"; FAIL_HELM_ONCE=1 "$ROOT/scripts/install-cilium.sh" "$TMP/kubeconfig" segv >/dev/null 2>&1
[[ $(grep -c '^helm' "$LOG") -eq 2 ]] || fail "helm was not retried"
grep -q 'values-segv.yaml' "$LOG" || fail "segv values"

# 3. Unknown cluster, missing kubeconfig and missing arguments fail without touching anything.
: >"$LOG"
if "$ROOT/scripts/install-cilium.sh" "$TMP/kubeconfig" nope 2>/dev/null; then fail "unknown cluster accepted"; fi
if "$ROOT/scripts/install-cilium.sh" "$TMP/missing" dev 2>/dev/null; then fail "missing kubeconfig accepted"; fi
if "$ROOT/scripts/install-cilium.sh" dev 2>/dev/null; then fail "missing argument accepted"; fi
[[ ! -s $LOG ]] || fail "calls were made on invalid input"
echo "install-cilium: ok"
