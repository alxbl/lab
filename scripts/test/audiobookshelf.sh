#!/usr/bin/env bash
# Renders infra/k8s/audiobookshelf and checks the settings that make the unprivileged pod, the share mounts and the
# public route work, and the Keycloak client that goes with it. No cluster access.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
kubectl kustomize infra/k8s/audiobookshelf >"$TMP/app.yaml"
kubectl kustomize infra/system/keycloak >"$TMP/keycloak.yaml"

python3 -I - "$TMP" <<'PY'
import sys, yaml

tmp = sys.argv[1]
docs = [d for d in yaml.safe_load_all(open(f"{tmp}/app.yaml")) if d]
by = lambda ds, kind: [d for d in ds if d["kind"] == kind]
one = lambda ds, kind: (lambda l: l[0] if len(l) == 1 else sys.exit(f"FAIL: expected one {kind}, got {len(l)}"))(by(ds, kind))

pod = one(docs, "Deployment")["spec"]["template"]
sc = pod["spec"]["securityContext"]
assert (sc["runAsUser"], sc["runAsGroup"], sc["runAsNonRoot"]) == (1000, 1000, True)
# fsGroup would recursively chown the whole smbd share on first mount.
assert "fsGroup" not in sc, "fsGroup must stay unset: it would chown the shared volume"
assert sc["seLinuxOptions"]["level"] == "s0"
(c,) = pod["spec"]["containers"]
assert "@sha256:" in c["image"], "image not pinned by digest"
env = {e["name"]: e["value"] for e in c["env"]}
assert env["PORT"] == "13378" and c["ports"][0]["containerPort"] == 13378  # not root: no port 80
assert env["CONFIG_PATH"].startswith("/data/") and env["METADATA_PATH"].startswith("/data/")
for probe in ("startupProbe", "readinessProbe"):
    assert c[probe]["httpGet"]["path"] == "/healthcheck"

mounts = {m["mountPath"]: m for m in c["volumeMounts"]}
assert mounts["/data"]["name"] == "data" and "subPath" not in mounts["/data"]
assert mounts["/audiobooks"]["subPath"] == "audiobooks" and mounts["/podcasts"]["subPath"] == "podcasts"
vols = {v["name"]: v["persistentVolumeClaim"]["claimName"] for v in pod["spec"]["volumes"]}
assert vols == {"data": "audiobookshelf", "share": "smbd-data"}, vols
assert one(docs, "PersistentVolumeClaim")["spec"]["volumeName"] == "audiobookshelf"

# Own hostname, backed by the Service on port 80.
svc = one(docs, "Service")["spec"]["ports"][0]
assert (svc["port"], svc["targetPort"]) == (80, "http")
route = one(docs, "HTTPRoute")["spec"]
assert route["hostnames"] == ["books.segfault.me"]
assert [(b["name"], b["port"]) for r in route["rules"] for b in r["backendRefs"]] == [("audiobookshelf", 80)]
assert {d["metadata"].get("namespace") for d in docs} == {"media"}

# The Keycloak client allows the web callback, the mobile redirect and the app scheme.
kc = [d for d in yaml.safe_load_all(open(f"{tmp}/keycloak.yaml")) if d]
cl = [d for d in by(kc, "KeycloakOIDCClient") if d["metadata"]["name"] == "audiobookshelf"][0]["spec"]["client"]
assert set(cl["redirectUris"]) == {"https://books.segfault.me/auth/openid/callback",
                                   "https://books.segfault.me/auth/openid/mobile-redirect", "audiobookshelf://oauth"}
assert cl["auth"]["secretRef"] == {"name": "keycloak-audiobookshelf", "key": "client-secret"}
print("audiobookshelf: ok")
PY
