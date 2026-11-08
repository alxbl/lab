#!/usr/bin/env bash
# Renders the oauth2-proxy Component on a fixture Deployment and checks the sidecar, plus the Keycloak policy that
# admits it. No cluster access.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

kubectl kustomize scripts/test/fixtures/oauth2-proxy >"$TMP/app.yaml"
kubectl kustomize infra/system/keycloak >"$TMP/keycloak.yaml"

python3 -I - "$TMP" <<'PY'
import sys, yaml

tmp = sys.argv[1]
docs = [d for d in yaml.safe_load_all(open(f"{tmp}/app.yaml")) if d]
(dep,) = [d for d in docs if d["kind"] == "Deployment"]
pod = dep["spec"]["template"]
names = [c["name"] for c in pod["spec"]["containers"]]
assert names == ["demo", "oauth2-proxy"], names
assert pod["metadata"]["labels"]["lab.segfault.me/oauth2-proxy"] == "true"

proxy = pod["spec"]["containers"][1]
env = {e["name"]: e for e in proxy["env"]}
val = lambda k: env["OAUTH2_PROXY_" + k]["value"]
assert val("CLIENT_ID") == "demo"
assert val("UPSTREAMS") == "http://127.0.0.1:8080"
assert val("REDIRECT_URL") == "https://demo.segfault.me/oauth2/callback"
assert val("PROVIDER") == "keycloak-oidc" and val("CODE_CHALLENGE_METHOD") == "S256"
assert val("OIDC_EMAIL_CLAIM") == "preferred_username" and val("REVERSE_PROXY") == "true"
assert val("REDEEM_URL").startswith("http://keycloak-service.keycloak:8080/auth/")
assert val("OIDC_JWKS_URL").startswith("http://keycloak-service.keycloak:8080/auth/")
for k in ("CLIENT_SECRET", "COOKIE_SECRET"):  # secrets come from the Secret, never inline
    assert "value" not in env["OAUTH2_PROXY_" + k]
    assert env["OAUTH2_PROXY_" + k]["valueFrom"]["secretKeyRef"]["name"] == "demo-oauth2-proxy"
assert not any(v == "replaced" for e in env.values() for v in [e.get("value")]), "unreplaced placeholder"
assert proxy["ports"] == [{"name": "auth", "containerPort": 4180}]
assert proxy["securityContext"]["readOnlyRootFilesystem"] and proxy["securityContext"]["runAsNonRoot"]
assert proxy["image"].split(":")[1].startswith("v7."), "image not pinned"

kc = [d for d in yaml.safe_load_all(open(f"{tmp}/keycloak.yaml")) if d]
(pol,) = [d for d in kc if d["kind"] == "CiliumNetworkPolicy" and d["metadata"]["name"] == "keycloak-oauth2-proxy"]
rule = pol["spec"]["ingress"][0]
assert rule["fromEndpoints"][0]["matchLabels"] == {"lab.segfault.me/oauth2-proxy": "true"}
assert rule["toPorts"][0]["ports"] == [{"port": "8080", "protocol": "TCP"}]
print("oauth2-proxy: ok")
PY
