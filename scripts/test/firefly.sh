#!/usr/bin/env bash
# Renders infra/k8s/firefly and checks the invariants that keep the app behind its proxy. No cluster access.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT"
kubectl kustomize infra/k8s/firefly | python3 -I -c '
import sys, yaml
docs = [d for d in yaml.safe_load_all(sys.stdin) if d]
by = lambda kind: [d for d in docs if d["kind"] == kind]
one = lambda kind: (lambda l: l[0] if len(l) == 1 else sys.exit(f"FAIL: expected one {kind}, got {len(l)}"))(by(kind))

dep = one("Deployment")
pod = dep["spec"]["template"]
cs = {c["name"]: c for c in pod["spec"]["containers"]}
assert set(cs) == {"firefly", "oauth2-proxy"}, list(cs)
app_port = cs["firefly"]["ports"][0]["containerPort"]
env = {e["name"]: e for e in cs["firefly"]["env"]}
assert env["AUTHENTICATION_GUARD"]["value"] == "remote_user_guard"
assert env["AUTHENTICATION_GUARD_HEADER"]["value"] == "HTTP_X_FORWARDED_PREFERRED_USERNAME"

# The app port is published nowhere and denied to every source.
svc = one("Service")
assert [p["port"] for p in svc["spec"]["ports"]] == [4180] and svc["spec"]["ports"][0]["targetPort"] == "auth"
route = one("HTTPRoute")
assert route["spec"]["hostnames"] == ["money.segfault.me"]
assert [(b["name"], b["port"]) for r in route["spec"]["rules"] for b in r["backendRefs"]] == [("firefly", 4180)]
iso = [d for d in by("CiliumNetworkPolicy") if d["metadata"]["name"] == "firefly-isolate"][0]
deny = iso["spec"]["ingressDeny"]
assert deny == [{"fromEntities": ["all"], "toPorts": [{"ports": [{"port": str(app_port), "protocol": "TCP"}]}]}], deny
assert iso["spec"]["endpointSelector"]["matchLabels"].items() <= pod["metadata"]["labels"].items()
assert pod["metadata"]["labels"]["lab.segfault.me/oauth2-proxy"] == "true"

# The proxy lets through only the cron path, and the CronJob goes through the proxy.
penv = {e["name"]: e for e in cs["oauth2-proxy"]["env"]}
assert penv["OAUTH2_PROXY_SKIP_AUTH_ROUTES"]["valueFrom"]["secretKeyRef"] == {"name": "firefly-secrets", "key": "cron-skip-route"}
assert penv["OAUTH2_PROXY_UPSTREAMS"]["value"] == f"http://127.0.0.1:{app_port}"
assert penv["OAUTH2_PROXY_REDIRECT_URL"]["value"] == "https://money.segfault.me/oauth2/callback"
cmd = one("CronJob")["spec"]["jobTemplate"]["spec"]["template"]["spec"]["containers"][0]["command"][-1]
assert "http://firefly:4180/api/v1/cron/" in cmd and "-K -" in cmd, cmd

# Storage claims match the static PVs (scripts/test/storage-bindings.sh checks the PV side).
assert one("PersistentVolumeClaim")["spec"]["volumeName"] == "firefly"
assert one("Cluster")["spec"]["storage"]["pvcTemplate"]["volumeName"] == "firefly-db"
assert {d["metadata"].get("namespace") for d in docs} == {"home"}
print("firefly: ok")'
