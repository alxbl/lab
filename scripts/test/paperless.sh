#!/usr/bin/env bash
# Renders infra/k8s/paperless and checks the settings that make the sub-path, the share mounts and the broker work. No cluster access.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT"
kubectl kustomize infra/k8s/paperless | python3 -I -c '
import sys, yaml
docs = [d for d in yaml.safe_load_all(sys.stdin) if d]
by = lambda kind: [d for d in docs if d["kind"] == kind]
one = lambda kind: (lambda l: l[0] if len(l) == 1 else sys.exit(f"FAIL: expected one {kind}, got {len(l)}"))(by(kind))

pod = one("Deployment")["spec"]["template"]
cs = {c["name"]: c for c in pod["spec"]["containers"]}
assert set(cs) == {"paperless", "broker"}, list(cs)
env = {e["name"]: e for e in cs["paperless"]["env"]}
val = lambda k: env[k]["value"]

# Served at lab.segfault.me/docs: the URL carries no path, the script name and static URL do.
assert val("PAPERLESS_URL") == "https://lab.segfault.me"
assert val("PAPERLESS_FORCE_SCRIPT_NAME") == "/docs" and val("PAPERLESS_STATIC_URL") == "/docs/static/"
assert val("PAPERLESS_PROXY_SSL_HEADER") == "[\"HTTP_X_FORWARDED_PROTO\", \"https\"]"
route = one("HTTPRoute")
assert route["spec"]["hostnames"] == ["lab.segfault.me"]
(rule,) = route["spec"]["rules"]
assert rule["matches"] == [{"path": {"type": "PathPrefix", "value": "/docs"}}]
assert [(b["name"], b["port"]) for b in rule["backendRefs"]] == [("paperless", 8000)]
assert one("Service")["spec"]["ports"][0]["port"] == 8000
for probe in ("startupProbe", "readinessProbe"):  # Django answers only its configured host
    assert {"name": "Host", "value": "lab.segfault.me"} in cs["paperless"][probe]["httpGet"]["httpHeaders"]

# The broker is loopback-only and is what the app points at.
assert val("PAPERLESS_REDIS") == "redis://127.0.0.1:6379"
args = cs["broker"]["args"]
assert args[args.index("--bind") + 1] == "127.0.0.1"
sc = cs["broker"]["securityContext"]
assert sc["runAsUser"] == 999 and sc["runAsNonRoot"], "broker must start unprivileged (setpriv needs capabilities)"
assert all("@sha256:" in c["image"] for c in cs.values()), "images not pinned by digest"

# Documents sit on the smbd share, the index on its own volume; the pod shares the share'"'"'s SELinux level.
mounts = {m["mountPath"]: m for m in cs["paperless"]["volumeMounts"]}
assert mounts["/usr/src/paperless/media"]["subPath"] == "paperless/media"
assert mounts["/usr/src/paperless/consume"]["subPath"] == "paperless/consume"
assert mounts["/usr/src/paperless/data"]["name"] == "data" and "subPath" not in mounts["/usr/src/paperless/data"]
vols = {v["name"]: v["persistentVolumeClaim"]["claimName"] for v in pod["spec"]["volumes"]}
assert vols == {"data": "paperless", "share": "smbd-data"}, vols
assert pod["spec"]["securityContext"]["seLinuxOptions"]["level"] == "s0"

# Secrets: environment from paperless-secrets, database login from the CNPG Secret.
assert cs["paperless"]["envFrom"] == [{"secretRef": {"name": "paperless-secrets"}}]
assert env["PAPERLESS_DBUSER"]["valueFrom"]["secretKeyRef"]["name"] == "paperless-database-app"
assert env["PAPERLESS_DBHOST"]["value"] == "paperless-database-rw"
assert val("PAPERLESS_APPS") == "allauth.socialaccount.providers.openid_connect"

# Storage claims match the static PVs (scripts/test/storage-bindings.sh checks the PV side).
assert one("PersistentVolumeClaim")["spec"]["volumeName"] == "paperless"
assert one("Cluster")["spec"]["storage"]["pvcTemplate"]["volumeName"] == "paperless-db"
assert {d["metadata"].get("namespace") for d in docs} == {"media"}
print("paperless: ok")'
