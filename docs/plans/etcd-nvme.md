# Plan: move etcd on segv (tachyon) to an NVMe SSD

Status: DRAFT, not committed anywhere. Target repo for the code change: `github.com/alxbl/lab` (PR, never on `main`).

## Goal
`/var/lib/etcd` moves off the USB 2.0 SSD (`sda`, ELECOM ESD-EPK, 58% endurance used, WAL fsync mean 6.9 ms / p99.9 512 ms)
onto an NVMe SSD on a PCIe adapter. `sda` stays the netboot/OS/containerd disk. Containerd stays on `sda` for now (optional follow-up).

## Verified facts (read-only checks, 2026-11-06)
- Server: HP ProLiant DL380p Gen8 (Xeon E5 v2 root ports report 8 GT/s = PCIe Gen3, x8/x16 ports present).
- PCIe slot 1: Gen3, x16 connector, long, free. Slot 3: Gen2 x4, short, free. Slot 2 (Gen3 x8) holds the 10 GbE NIC.
- Typhoon `etcd-member.service` data dir is `/var/lib/etcd` (`-v /var/lib/etcd:/var/lib/etcd:rw,Z`); currently 399 MB.
- Root is `sda4` (xfs, label `root`) and is wiped on reprovision (`butane/wipe-root.yaml`). A new etcd disk must be wiped on
  reprovision too: Typhoon bootstraps a fresh etcd with new certs, and a stale data dir would conflict.

## Unverified (check before/while doing)
- DL380p Gen8 form factor: 8-SFF / 25-SFF / 12-LFF chassis all have riser slots, but riser 1 slot 1 on a 2U may be full-height
  only; confirm adapter bracket (full height vs low profile) by opening the lid.
- Gen8 BIOS cannot boot NVMe (irrelevant here, `sda` boots), and may spin fans up for third-party PCIe cards: watch iLO fan/temps.
- Slot 1 electrical width (x8 or x16 on a x16 connector). Any >= x4 is enough.

## Hardware shopping list
Adapter (passive, single M.2, no bifurcation needed): StarTech PEX4M2E1, Sabrent EC-PCIE, Delock 89370/89476, Ableconn PEXM2-130.
Avoid multi-drive carriers (ASUS Hyper M.2 x16 etc.): they need slot bifurcation.
SSD (250-500 GB, Gen3 x4 speed is plenty, ~19 TB/yr of etcd writes):
1. With power-loss protection (best for fsync): Micron 7450 PRO 2280 480 GB, Kingston DC2000B 480 GB, Samsung PM983/PM9A3 (22110).
2. Budget: WD Red SN700 250/500 GB (500 TBW at 250 GB), Samsung 970 EVO Plus.
Avoid QLC and DRAM-less drives.

## Steps
### 0. Before touching the node
1. Take an etcd snapshot and an `/etc` tarball (same procedure as `pre-cutover/`), copy off-node.
2. Record baseline: etcd WAL fsync mean/p99/p99.9 from the existing metrics, for before/after comparison.
3. Decide if the node can be powered off for the install (single node: API and every workload is down for the duration).

### 1. Install hardware (node powered off; workloads return ~10 min after boot, see `.rules`)
1. Fit the M.2 SSD in the adapter, adapter in slot 1, close the lid, boot.
2. Verify: `lspci -nn | grep -i nvme`, `lspci -vv -s <addr> | grep LnkSta` (expect 8GT/s, x4), `nvme list`, `ls -l /dev/disk/by-id/ | grep nvme`.
3. Note the stable id `nvme-<model>_<serial>` (use it in butane, never `/dev/nvme0n1`).
4. Check iLO fans and temperatures; SSD under ~70 C under load (`smartctl -a /dev/nvme0`).

### 2. Live migration (no reprovision; do this once to get the benefit now)
Downtime: API unavailable for a few minutes.
1. `sudo mkfs.xfs -L etcd` on a new partition (`sgdisk -n1:0:0 -c1:etcd`) on the by-id device.
2. `sudo systemctl stop kubelet etcd-member` (stop the kubelet first so static pods do not fight).
3. Mount at a temp path, `rsync -aHAX --numeric-ids /var/lib/etcd/ <tmp>/`, then `umount` and mount the partition on `/var/lib/etcd`
   (mask the old path content: move it to `/var/lib/etcd.old`, do not delete yet). SELinux: `restorecon -R /var/lib/etcd`.
4. Make the mount persistent with a `var-lib-etcd.mount` unit (same unit that butane generates in step 3, so the live
   state matches what a reprovision produces).
5. `systemctl start etcd-member kubelet`; confirm `etcdctl endpoint health`, API reachable, Argo apps healthy.
6. Compare fsync latency to the baseline. Keep `/var/lib/etcd.old` a week, then remove it.

### 3. Butane change in lab (PR from a worktree, e.g. `etcd-nvme`)
- New snippet `infra/clusters/butane/etcd-disk.yaml` (draft below) with the disk id as a placeholder `@ETCD_DISK@`.
- `infra/clusters/segv/segv.tf`: add a variable `etcd_disk` (default: the by-id path from step 1) and append
  `replace(file("../butane/etcd-disk.yaml"), "@ETCD_DISK@", var.etcd_disk)` to the `tachyon` snippets, like `zfs.yaml`.
- Dev cluster is untouched (no NVMe in the VMs); the snippet is only wired into `segv`.
- Test: new `scripts/test/etcd-disk-butane.sh` modeled on `zfs-butane.sh` (butane `--strict`, checks the disk wipe, the
  `etcd` partition label, the xfs filesystem with `wipe_filesystem: true`, and the mount path `/var/lib/etcd`).
- Docs: one short note in `.rules` (the etcd disk is wiped on every reprovision, like root; disk id lives in `segv.tf`).
  Requires the user's consent to edit `.rules`.
- Applying the change means a reprovision (destructive): do it only when the user decides to reprovision anyway, restoring
  from the step-0 snapshot if needed. Not required for step 2 to take effect.

## Draft: `infra/clusters/butane/etcd-disk.yaml`
```yaml
# Dedicated NVMe disk for etcd. Wiped on every reprovision, like the root filesystem: Typhoon bootstraps a fresh etcd with new
# certificates, and stale data would conflict. The literal @ETCD_DISK@ is a /dev/disk/by-id path, replaced before rendering.
variant: fcos
version: 1.5.0
storage:
  disks:
    - device: "@ETCD_DISK@"
      wipe_table: true
      partitions:
        - label: etcd
          number: 1
  filesystems:
    - device: /dev/disk/by-partlabel/etcd
      format: xfs
      wipe_filesystem: true
      label: etcd
      path: /var/lib/etcd
      with_mount_unit: true
```
Open point: confirm Typhoon's `etcd-member.service` is ordered after local mounts (`RequiresMountsFor=/var/lib/etcd` can be
added with a drop-in if not); `/var/lib/etcd` is also created by its `ExecStartPre=mkdir -p`, which is harmless on a mount.

## Rollback
- Live (step 2): stop kubelet/etcd, unmount, move `/var/lib/etcd.old` back, start. Nothing else changed.
- Reprovision: restore the step-0 etcd snapshot.

## Follow-ups (optional)
- Move containerd (`/var/lib/containerd`) to the NVMe too: that is what made image pulls slow (10 MB/s writes on USB 2.0).
- Add an etcd fsync alert (p99 > 25 ms).
