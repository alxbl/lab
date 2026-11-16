#!/usr/bin/env bash
# Renders charts/adguard and checks that .lan names are forwarded to the UDM, next to the Quad9 default upstream,
# and that the CoreDNS Corefile keeps its lan zone pointing at the UDM (no cluster access).
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
UDM=10.0.0.1

fail() { echo "FAIL: $*"; exit 1; }

python3 -I - "$ROOT" "$UDM" <<'PY' || exit 1
import subprocess, sys, yaml

root, udm = sys.argv[1:3]
rendered = subprocess.run(["helm", "template", "adguard", f"{root}/charts/adguard"], capture_output=True, text=True, check=True).stdout
cm = next(d for d in yaml.safe_load_all(rendered) if d and d["kind"] == "ConfigMap" and d["metadata"]["name"] == "adguard-config")
dns = yaml.safe_load(cm["data"]["AdGuardHome.yaml"])["dns"]

upstreams = dns["upstream_dns"]
if f"[/lan/]{udm}" not in upstreams:
    sys.exit(f"FAIL: AdGuard does not forward lan to the UDM: {upstreams}")
if not any(u.startswith("tls://") for u in upstreams):
    sys.exit(f"FAIL: AdGuard lost its default DoT upstream: {upstreams}")

corefile = yaml.safe_load(open(f"{root}/infra/system/coredns/configmap.yaml"))["data"]["Corefile"]
block = corefile.split("lan:53 {", 1)
if len(block) != 2 or f"forward . {udm}" not in block[1].split("}", 1)[0]:
    sys.exit("FAIL: CoreDNS lan zone does not forward to the UDM")
PY
echo "adguard-dns: ok"
