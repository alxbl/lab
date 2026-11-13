#!/usr/bin/env bash
# Renders infra/clusters/butane/etcd-disk.yaml with butane --strict and checks the disk, filesystem and mount (no cluster access).
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SNIPPET="$HERE/../../infra/clusters/butane/etcd-disk.yaml"
DISK=/dev/disk/by-id/nvme-TEST_SSD_0001

if command -v butane >/dev/null; then butane=(butane)
elif command -v podman >/dev/null; then butane=(podman run --rm -i quay.io/coreos/butane:release)
else echo "SKIP: butane not available"; exit 0; fi

fail() { echo "FAIL: $*"; exit 1; }

ign=$(sed "s|@ETCD_DISK@|$DISK|" "$SNIPPET" | "${butane[@]}" --strict)

[[ $(jq -r '.storage.disks[0].device' <<<"$ign") == "$DISK" ]] || fail "disk id not substituted"
[[ $(jq -r '.storage.disks[0].wipeTable' <<<"$ign") == true ]] || fail "partition table is not wiped"
[[ $(jq -r '.storage.disks[0].partitions[0].label' <<<"$ign") == etcd ]] || fail "partition not labelled etcd"
fs='.storage.filesystems[] | select(.device == "/dev/disk/by-partlabel/etcd")'
[[ $(jq -r "$fs | .format" <<<"$ign") == xfs ]] || fail "etcd filesystem is not xfs"
[[ $(jq -r "$fs | .wipeFilesystem" <<<"$ign") == true ]] || fail "etcd filesystem is not wiped on reprovision"
[[ $(jq -r "$fs | .path" <<<"$ign") == /var/lib/etcd ]] || fail "etcd filesystem not mounted on /var/lib/etcd"
jq -e '.systemd.units[] | select(.name == "var-lib-etcd.mount" and .enabled == true)' <<<"$ign" >/dev/null || fail "no enabled mount unit"
jq -e '.systemd.units[] | select(.name == "etcd-member.service") | .dropins[] | select(.contents | contains("RequiresMountsFor=/var/lib/etcd"))' <<<"$ign" >/dev/null || fail "etcd-member does not wait for the mount"

# segv.tf wires the snippet only when a disk is configured, so the node still renders without the hardware.
grep -qF 'replace(file("../butane/etcd-disk.yaml"), "@ETCD_DISK@", var.etcd_disk)' "$HERE/../../infra/clusters/segv/segv.tf" || fail "segv.tf does not use the snippet"
grep -qF 'var.etcd_disk == ""' "$HERE/../../infra/clusters/segv/segv.tf" || fail "snippet is not optional"
echo "ok"
