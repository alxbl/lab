#!/usr/bin/env bash
# Renders infra/clusters/butane/zfs.yaml with butane --strict and checks the units (no cluster access).
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SNIPPET="$HERE/../../infra/clusters/butane/zfs.yaml"
IMAGE=ghcr.io/example/fcos@sha256:0000000000000000000000000000000000000000000000000000000000000000

if command -v butane >/dev/null; then butane=(butane)
elif command -v podman >/dev/null; then butane=(podman run --rm -i quay.io/coreos/butane:release)
else echo "SKIP: butane not available"; exit 0; fi

ign=$(sed "s|@ZFS_IMAGE@|$IMAGE|" "$SNIPPET" | "${butane[@]}" --strict)

unit() { jq -r --arg n "$1" '.systemd.units[] | select(.name == $n) | '"$2" <<<"$ign"; }
fail() { echo "FAIL: $*"; exit 1; }

[[ $(unit zincati.service .mask) == true ]] || fail "zincati not masked"
for u in zfs-import.target zfs-mount.service zfs.target zfs-rebase.service; do
  [[ $(unit $u .enabled) == true ]] || fail "$u not enabled"
done
[[ $(jq -r '.storage.links[] | select(.target == "/usr/lib/systemd/system/zfs-import-scan.service") | .path' <<<"$ign") == /etc/systemd/system/zfs-import.target.wants/zfs-import-scan.service ]] || fail "zfs-import-scan not enabled"
jq -e '.storage.files[] | select(.path == "/etc/containers/containers.conf.d/10-data.conf")' <<<"$ign" >/dev/null || fail "kubelet /var/data volume missing"
rebase=$(unit zfs-rebase.service .contents)
grep -qx 'Before=sshd.service' <<<"$rebase" || fail "rebase not ordered before sshd"
grep -qx 'ConditionPathExists=!/var/lib/zfs-rebased' <<<"$rebase" || fail "rebase has no marker condition"
grep -qx "ExecStart=/usr/bin/rpm-ostree rebase ostree-unverified-registry:$IMAGE" <<<"$rebase" || fail "image reference not substituted"
[[ $(grep -n '^ExecStart=' <<<"$rebase" | sed 's/^[0-9]*:ExecStart=\/usr\/bin\///; s/ .*//' | paste -sd,) == rpm-ostree,touch,systemctl ]] || fail "rebase, marker, reboot out of order"
echo "ok"
