# Homelab Infra-as-Code / GitOps

This repository hosts my infra-as-code and gitops configurations for
my home network. It also contains various bootstrapping scripts for
workstations and servers alike.

## Workstation Bootstrapping

Workstations running ArchLinux (btw) are provisioned via
`scripts/pacstrap.sh`

```sh
# After booting into ArchLinux Live USB
# https://raw.githubusercontent.com/alxbl/lab/main/scripts/pacstrap.sh
curl -sSfL https://bit.ly/pacstrap | HOST=hostname sh
```

## Cluster Overview

Each node is running Fedora Core OS with an additional layer (via
`rpm-ostree rebase`) which includes ZFS drivers and userland utilities
as well as [Typhoon](https://github.com/poseidon/typhoon) for the Kubernetes bootstrap.

Currently, my homelab cluster is made up of the following nodes:

- HP Proliant D630p G8 (2x 2.5GHz Xeon / 256GB RAM)
  - OS Drive: 500GB external SSD (`/`)
  - Data Pool: 8x1.2TB HDDs in a ZFS Raidz2 configuation (`/var/data`)

The high level diagram [can be found here](#TODO)

### Network Requirements

The LAN must route the service CIDR (`10.3.0.0/16`) to the cluster nodes.
Without that route on the router, none of these services are reachable from outside the cluster. 

`10.3.0.2` is shared by the Gateway on 80/443 and media server (`smbd`) on 445)
LAN clients can also reach ClusterIPs directly (e.g. AdGuard on `10.3.0.53`).

> **NOTE:** The dev cluster uses `10.33.0.0/16` and announces its LoadBalancer IPs over L2.

### Storage

Workload volumes are static `local-zfs` PersistentVolumes (`Retain`, no provisioner) declared in
`infra/system/storage`. Each one is pre-bound to its claim and backed by a ZFS dataset `data/k8s/<name>` of the
`data` pool, mounted under `/var/data/k8s/<name>` on the node. To add a volume, create the dataset on the node,
then add a PV next to the existing ones.

- Never `zpool upgrade` (it removes the rollback path) and never `zfs destroy` or delete a PV/PVC that is bound to a dataset.
- Datasets under `data/k8s` carry an SELinux `context` option; see `.rules` for the exceptions.
- Daily backups use Velero with the `node-agent` (kopia) into Azure Blob Storage. Its `BackupStorageLocation`,
  `backup-policy-zfs` and the `backup-pv-daily` schedule (`infra/system/velero`) are the `velero-config` Application. On a
  rebuild, sync `velero` first (it installs the CRDs), then `velero-config`; the `velero` server restarts until the location exists.
- `restore-test` (`infra/system/restore-test`) restores the newest vaultwarden snapshot with kopia into a tmpfs every Sunday
  and pushes the result to Prometheus over OTLP through Alloy. The "Backups" Grafana dashboard shows it next to Velero's metrics.
  `immich/.kopiaignore` on the smbd volume keeps Immich's thumbnails and transcodes out of the backup.

## Cluster Bootstrapping

To iterate on the bootstrapping process without hardware, see [DEVELOPMENT.md](DEVELOPMENT.md).

For a visual overview of the bootstrapping process, [see this diagram](#TODO)

Once the cluster is bootstrapped, it is self-sufficient as long as
there is at least one controller node up and running. Bootstrapping is
only necessary in case a full recovery is necessary after simultaneous
failure of all nodes.

**Bootstrapping Synthetic Test Status**: `Not implemented`

### Requirements

The following requirements must be met for bootstrapping to work:

The following tools must be available on the OS:

- zsh
- docker
- docker-compose
- git
- jq
- ip
- sudo
- terraform
- openssl

Additionally, the user running the bootstrap script must be a `sudoer` (without password for maximum automation)

Lastly, `proton-drive` must be installed and logged in: the cluster secrets and the PKI live in Proton Drive.

### Secrets (Proton Drive)

Secrets are stored end-to-end encrypted in Proton Drive.
The path on the drive is configured with (`LAB_SECRETS_REMOTE`) and defaults to `/my-files/Documents/Homelab/_secrets`.

```plain
segv/
  manifests/<namespace>/<secret-name>.yaml   Kubernetes Secrets (names listed in scripts/secrets.list)
  pki/                                       easy-rsa PKI: ca.crt, issued/, private/ (CA keys are encrypted)
  pki-tooling/                               setup.sh and vars used to build that PKI
  pre-cutover/                               etcd snapshot, /etc tarball, terraform state (taken before reprovisioning) (FIXME: Remove after cutover)
```

- `scripts/export-secrets <kubeconfig>` copies the listed Secrets from the cluster to `manifests/`.
- `scripts/import-secrets [--dry-run] <kubeconfig> [namespace...]` applies them to the cluster.
- `scripts/import-certs` copies public certificates into the repository's `pki/`.

### Usage

`scripts/bootstrap.sh` is no longer used: it stops DNS services and edits iptables. Run the steps by hand
(this reinstalls the node, wiping its root disk; the ZFS pool on the other disks is untouched):

1. Ensure requirements are met, `proton-drive` is logged in, and `matchbox.lan` resolves (UDM DNS) to this host.
2. `scripts/bootstrap-pki` if `pki/` has no certificates, and `scripts/get-fedora-coreos stable <os_version>`
   for the `os_version` in `infra/clusters/segv/segv.tf` if the assets are missing.
3. Export the pool first if it is imported: `systemctl stop kubelet` on the node, then `zpool export data`.
4. Start the netboot stack: `docker compose -f build/bootstrap/docker-compose.yml up -d`. Open the PXE ports in the
   firewall if needed (TCP 8080; UDP 67, 69, 4011) and close them again afterwards. Keep any Raspberry Pi powered off.
5. `terraform init && terraform apply` in `infra/clusters/segv`. Power on (or one-time PXE boot) the node. Use
   `TF_VAR_console=ttyS1` for a serial console and `TF_VAR_zfs_image=...` to change the pinned ZFS image.
6. When the node is up: `docker compose -f build/bootstrap/docker-compose.yml down`, import the pool if needed
   (`zpool import data`), then `scripts/install-cilium.sh infra/clusters/segv/kube.conf segv`.
7. Install ArgoCD (`kubectl apply --server-side --force-conflicts -k infra/system/argocd`, twice), then
   `scripts/import-secrets <kubeconfig>` and sync the catalogs.

terraform will report that it is waiting for provisioning as such:

```plain
segv  module.segv.null_resource.copy-controller-secrets[0]: 
Provisioning with 'file'...
segv  module.segv.null_resource.copy-controller-secrets[0]: Still creating... [10s elapsed]
```

Bootstrapping must provision at least one controller node. The cluster
is bootstrapped to be able to provision new nodes as necessary, so
nodes can be dynamically added without running the bootstrap script
from this repository again other than in disaster recovery scenarios
where the entire cluster is lost at once.

## Disaster Recovery

Cluster data is backed up to Azure Blob Storage daily using `rustic`
as well as to an external hard drive via `rsync`.

The external hard drive should be the first source to attempt recovery
from, as it is the simplest, cheapest, and fastest.

If the hard drive is also lost as part of disaster, then recovery from
Azure Blob Storage can be achieved by [following these steps](#TODO).
