#!/usr/bin/env bash
# Checks that every static PV in infra/system/storage can be claimed by the PVC that the matching catalog
# Application (infra/k8s/catalog or infra/system/catalog) renders (name, class, access mode, size, volumeName). No cluster access.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

kubectl kustomize infra/system/storage >"$TMP/pvs.yaml"
{ helm template cat infra/k8s/catalog; echo ---; helm template sys infra/system/catalog; } >"$TMP/apps.yaml"

python3 -I - "$TMP" <<'PY'
import json, re, subprocess, sys, yaml

tmp = sys.argv[1]
UNITS = {"Ki": 2**10, "Mi": 2**20, "Gi": 2**30, "Ti": 2**40, "K": 10**3, "M": 10**6, "G": 10**9, "T": 10**12}

def qty(v):
    m = re.fullmatch(r"(\d+)([A-Za-z]*)", str(v))
    return int(m.group(1)) * UNITS.get(m.group(2), 1)

pvs = [d for d in yaml.safe_load_all(open(f"{tmp}/pvs.yaml")) if d and d["kind"] == "PersistentVolume"]
apps = [d for d in yaml.safe_load_all(open(f"{tmp}/apps.yaml")) if d and d["kind"] == "Application"]

pvcs = {}  # (namespace, name) -> {class, modes, request, volumeName}

def add(ns, name, cls, modes, request, volume_name=None):
    pvcs[(ns, name)] = dict(cls=cls, modes=modes, request=qty(request), volume_name=volume_name)

for app in apps:
    src, ns = app["spec"].get("source"), app["spec"]["destination"].get("namespace", "default")
    if src is None:  # multi-source Application (cilium): no workload volumes
        continue
    values = src.get("helm", {}).get("valuesObject", {})
    path = src.get("path", "")
    if path.startswith("charts/") and "alxbl/lab" in src.get("repoURL", ""):
        vf = f"{tmp}/{app['metadata']['name']}.values.yaml"
        yaml.safe_dump(values, open(vf, "w"))
        out = subprocess.run(["helm", "template", app["metadata"]["name"], path, "-n", ns, "-f", vf],
                             check=True, capture_output=True, text=True).stdout
        for d in yaml.safe_load_all(out):
            if d and d["kind"] == "PersistentVolumeClaim":
                s = d["spec"]
                add(d["metadata"].get("namespace", ns), d["metadata"]["name"], s.get("storageClassName"),
                    s["accessModes"], s["resources"]["requests"]["storage"], s.get("volumeName"))
    elif app["metadata"]["name"] == "home-assistant":
        # External chart: the StatefulSet claim is <template>-<statefulset>-<ordinal>.
        p = values["persistence"]
        add(ns, "home-assistant-home-assistant-0", p["storageClass"], [p["accessMode"]], p["size"])

    elif app["metadata"]["name"] in ("immich-database", "keycloak"):
        # CNPG instance claim: <cluster>-<ordinal>.
        out = subprocess.run(["kubectl", "kustomize", path], check=True, capture_output=True, text=True).stdout
        for d in yaml.safe_load_all(out):
            if d and d["kind"] == "Cluster":
                t = d["spec"]["storage"]["pvcTemplate"]
                add(d["metadata"].get("namespace", ns), d["metadata"]["name"] + "-1", t["storageClassName"], t["accessModes"],
                    t["resources"]["requests"]["storage"], t.get("volumeName"))
    elif app["metadata"]["name"] == "monitoring":
        # Operator-generated Prometheus claim, and the Grafana subchart's claim.
        cr = values["fullnameOverride"] + "-prometheus"
        spec = values["prometheus"]["prometheusSpec"]["storageSpec"]["volumeClaimTemplate"]["spec"]
        add(ns, f"prometheus-{cr}-db-prometheus-{cr}-0", spec["storageClassName"], spec["accessModes"],
            spec["resources"]["requests"]["storage"], spec.get("volumeName"))
        g = values["grafana"]
        add(ns, g["fullnameOverride"], g["persistence"]["storageClass"] if "storageClass" in g["persistence"]
            else g["persistence"]["storageClassName"], ["ReadWriteOnce"], g["persistence"]["size"],
            g["persistence"].get("volumeName"))
    elif app["metadata"]["name"] == "loki":
        # StatefulSet claim: <volumeClaimTemplate>-<statefulset>-<ordinal>.
        p = values["singleBinary"]["persistence"]
        add(ns, "storage-loki-0", p["storageClass"], ["ReadWriteOnce"], p["size"])

errors = []
for pv in pvs:
    name = pv["metadata"]["name"]
    ref = pv["spec"]["claimRef"]
    pvc = pvcs.get((ref["namespace"], ref["name"]))
    if not pvc:
        errors.append(f"PV {name}: no rendered PVC {ref['namespace']}/{ref['name']}")
        continue
    if pvc["cls"] != pv["spec"]["storageClassName"]:
        errors.append(f"PV {name}: class {pvc['cls']!r} != {pv['spec']['storageClassName']!r}")
    if not set(pvc["modes"]) <= set(pv["spec"]["accessModes"]):
        errors.append(f"PV {name}: PVC modes {pvc['modes']} not offered by the PV {pv['spec']['accessModes']}")
    if pvc["request"] > qty(pv["spec"]["capacity"]["storage"]):
        errors.append(f"PV {name}: PVC requests more than the PV offers")
    if pvc["volume_name"] not in (None, name):
        errors.append(f"PV {name}: PVC volumeName {pvc['volume_name']!r}")
claimed = {(pv["spec"]["claimRef"]["namespace"], pv["spec"]["claimRef"]["name"]) for pv in pvs}
for key, pvc in pvcs.items():
    if key not in claimed:
        errors.append(f"PVC {key[0]}/{key[1]} (class {pvc['cls']}) has no static PV")
if errors:
    print("\n".join("FAIL: " + e for e in errors))
    sys.exit(1)
print(f"{len(pvs)} PVs match {len(pvcs)} rendered PVCs")
PY

if grep -rEn 'zfs-rwo|zfs-rwx' charts infra --include='*.yaml' --include='*.tpl' >"$TMP/old" 2>/dev/null; then
  echo "FAIL: removed storage classes still referenced:"; cat "$TMP/old"; exit 1
fi
echo "storage-bindings: ok"
