#!/usr/bin/env bash
# Renders infra/clusters/butane/nvme-disk.yaml with butane --strict and checks that the OS root, etcd and containerd land on the
# NVMe while the OS (USB) disk keeps only its boot partitions (no cluster access).
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SNIPPET="$HERE/../../infra/clusters/butane/nvme-disk.yaml"
TF="$HERE/../../infra/clusters/segv/segv.tf"
OS=/dev/disk/by-id/scsi-TEST_USB_0001
NVME=/dev/disk/by-id/nvme-TEST_SSD_0001

if command -v butane >/dev/null; then butane=(butane)
elif command -v podman >/dev/null; then butane=(podman run --rm -i quay.io/coreos/butane:release)
else echo "SKIP: butane not available"; exit 0; fi

fail() { echo "FAIL: $*"; exit 1; }

ign=$(sed -e "s|@OS_DISK@|$OS|" -e "s|@NVME_DISK@|$NVME|" "$SNIPPET" | "${butane[@]}" --strict)
disk() { jq -c --arg d "$1" '.storage.disks[] | select(.device == $d)' <<<"$ign"; }
fs() { jq -c --arg d "$1" '.storage.filesystems[] | select(.device == $d)' <<<"$ign"; }
part() { jq -r --arg l "$2" ".partitions[] | select(.label == \$l) | $3" <<<"$1"; }

# OS disk: only the old root partition is removed; nothing else on it is touched or wiped.
usb=$(disk "$OS"); [[ -n $usb ]] || fail "OS disk not substituted"
[[ $(jq -r '.wipeTable // false' <<<"$usb") == false ]] || fail "OS disk partition table is wiped"
[[ $(jq -r '.partitions | length' <<<"$usb") == 1 ]] || fail "OS disk must only list the root partition"
[[ $(jq -r '.partitions[0].number' <<<"$usb") == 4 ]] || fail "the partition removed from the OS disk is not number 4 (root)"
[[ $(jq -r '.partitions[0].shouldExist' <<<"$usb") == false ]] || fail "old root partition on the OS disk is not deleted"

# NVMe: wiped table, os-root (not the reserved label root), etcd and containerd.
nv=$(disk "$NVME"); [[ -n $nv ]] || fail "NVMe disk not substituted"
[[ $(jq -r '.wipeTable' <<<"$nv") == true ]] || fail "NVMe partition table is not wiped"
[[ $(part "$nv" os-root .number) == 1 ]] || fail "os-root is not partition 1"
(( $(part "$nv" os-root .sizeMiB) >= 8192 )) || fail "os-root is smaller than the 8 GiB FCOS minimum"
[[ $(part "$nv" etcd .sizeMiB) == 32768 ]] || fail "etcd partition is not 32 GiB"
[[ $(part "$nv" containerd .sizeMiB) == null ]] || fail "containerd partition must take the rest of the disk"
jq -e '[.partitions[].label] | index("root") == null' <<<"$nv" >/dev/null || fail "reserved partition label root used on the NVMe"

# Root filesystem: recreated on os-root with the label FCOS looks for; no stale by-partlabel/root reference.
r=$(fs /dev/disk/by-partlabel/os-root); [[ -n $r ]] || fail "no filesystem on os-root"
[[ $(jq -r .label <<<"$r") == root ]] || fail "new root filesystem is not labelled root"
[[ $(jq -r .format <<<"$r") == xfs ]] || fail "root filesystem is not xfs"
[[ $(jq -r .wipeFilesystem <<<"$r") == true ]] || fail "root filesystem is not wiped on reprovision"
[[ -z $(fs /dev/disk/by-partlabel/root) ]] || fail "a filesystem still targets the deleted by-partlabel/root"

for name in etcd containerd; do
  f=$(fs "/dev/disk/by-partlabel/$name"); [[ -n $f ]] || fail "no $name filesystem"
  [[ $(jq -r .format <<<"$f") == xfs ]] || fail "$name filesystem is not xfs"
  [[ $(jq -r .wipeFilesystem <<<"$f") == true ]] || fail "$name filesystem is not wiped on reprovision"
  [[ $(jq -r .path <<<"$f") == "/var/lib/$name" ]] || fail "$name filesystem not mounted on /var/lib/$name"
  jq -e --arg u "var-lib-$name.mount" '.systemd.units[] | select(.name == $u and .enabled == true)' <<<"$ign" >/dev/null || fail "no enabled $name mount unit"
done
jq -e '.systemd.units[] | select(.name == "etcd-member.service") | .dropins[] | select(.contents | contains("RequiresMountsFor=/var/lib/etcd"))' <<<"$ign" >/dev/null || fail "etcd-member does not wait for the mount"
jq -e '.systemd.units[] | select(.name == "containerd.service") | .dropins[] | select(.contents | contains("RequiresMountsFor=/var/lib/containerd"))' <<<"$ign" >/dev/null || fail "containerd does not wait for the mount"

# segv.tf wires the snippet with both disk ids, and falls back to the old layout (wipe-root) when no NVMe is configured.
grep -qF '"@NVME_DISK@", var.nvme_disk)' "$TF" || fail "segv.tf does not substitute the NVMe disk"
grep -qF '"@OS_DISK@", local.os_disk)' "$TF" || fail "segv.tf does not substitute the OS disk"
grep -qF 'install_disk = local.os_disk' "$TF" || fail "install disk and the OS disk in the snippet can differ"
grep -qF 'var.nvme_disk == ""' "$TF" || fail "NVMe layout is not optional"
[[ $(grep -cF 'file("../butane/wipe-root.yaml")' "$TF") == 1 ]] || fail "wipe-root must appear exactly once, as the no-NVMe fallback"
grep -qF '[file("../butane/wipe-root.yaml")] :' "$TF" || fail "wipe-root is not the no-NVMe branch"
echo "ok"
