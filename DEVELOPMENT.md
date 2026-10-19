# Development Setup

> **Disclaimer**: A lot of this makes assumptions about my own setup,
> so it will most likely not work out of the box if you are not using
> my configurations and environment.

## Assumptions

* Hypervisor setup with QEMU and KVM, libvirt system connection (`qemu:///system`)
* `qemu0` bridge exists (10.2.0.1/24)
* Passwordless `sudo`, and the user is in the `docker` group
* The following tools must be installed: `terraform`, `kubectl`, `helm`,
  `docker` (with the compose plugin), `virt-install`, `virsh`, `openssl`, `jq`, `curl`
* Dev environment is in `dev/`. The matchbox and TFTP trees are shared with the
  production bootstrap in `build/bootstrap`.

## Development Cluster

A throwaway two-node (node1 controller + node2 worker) Typhoon cluster running in
KVM VMs on `qemu0`. It lets you iterate on bootstrapping and cluster features
without hardware. See `infra/clusters/dev`.

> **NOTE**: By default the dev cluster does not add ZFS support or rebase to
> `ghcr.io/alxbl/lab/fcos`; that is not necessary for development. See
> "ZFS rehearsal" below to opt in.

### Start (or reset) the cluster

```sh
dev/up.sh
```

Every run is a full clean start and takes about 4-5 minutes. It:

1. checks tools and starts `docker.service` if needed
2. stops the host `dnsmasq@qemu0` (remembered, restored by `dev/down.sh`)
3. generates the bootstrap PKI and downloads the FCOS version pinned in `dev.tf`, only if missing
4. starts matchbox and dnsmasq (`dev/docker-compose.yml`)
5. wipes the stale terraform state and `dev.conf`
6. destroys and recreates the VMs (`dev/vm.sh`)
7. runs `terraform apply` in `infra/clusters/dev`
8. installs the Gateway API CRDs and Cilium with Helm (`infra/system/cilium`, values from `values.yaml` + `values-dev.yaml`);
   Typhoon is configured with `components.cilium.enable = false`, so the nodes have no CNI until this step
9. once `qemu0` has its address, restarts dnsmasq (it can only bind after a VM
   attaches to the bridge) and resets the VMs once matchbox has profiles for
   them, so they restart their PXE boot
10. waits (`READY_TIMEOUT`, default 900s) until both nodes are Ready

matchbox and dnsmasq are left running because rebooting nodes need PXE.

### ZFS rehearsal (opt-in)

```sh
DEV_ZFS=1 dev/up.sh
```

Adds `infra/clusters/butane/zfs.yaml` to node2 only (Terraform variable `zfs_image`, set from `DEV_ZFS_IMAGE`,
default `ghcr.io/alxbl/lab/fcos:latest`; pin a digest to mirror production) and attaches `DEV_ZFS_DISKS`
(default 4) 2G virtio data disks (serials `zfsdata1..N`, `/dev/disk/by-id/virtio-zfsdataN`). On first boot node2 rebases onto the
image, reboots (sshd and the Typhoon bootstrap only start after that), then imports pools by scanning.

`sudo dev/vm.sh reinstall node2` recreates node2 with an empty root disk and keeps the data disks, so it PXE installs a
fresh OS (use after `zpool export`, with matchbox running; `zpool export` needs `systemctl stop kubelet` first, because the
kubelet container holds the mounts). After it boots (install, rebase, one reboot) run `terraform apply -replace='module.dev.module.workers[0].null_resource.copy-worker-secrets'`
in `infra/clusters/dev` (with `TF_VAR_zfs_image` set as `dev/up.sh` does) so node2 gets its kubelet secrets and rejoins. The pool imports
by itself, without `-f`. `dev/vm.sh destroy` (and so `dev/up.sh`) deletes the data disks.

`scripts/test/zfs-butane.sh` checks the snippet.

### Serial console (opt-in)

```sh
DEV_CONSOLE=ttyS0 DEV_ZFS=1 dev/up.sh     # Terraform variable `console`
```

Adds `console=tty0 console=<port>,115200n8` to the PXE installer (Typhoon `kernel_args`; the installer does not copy it to
the installed OS) and, with `DEV_ZFS=1`, to node2's installed OS: `zfs-rebase.service` runs
`rpm-ostree kargs --append-if-missing=...` after the rebase and before its reboot, so there is no extra reboot (butane
`kernel_arguments` would add one). Watch it with `sudo virsh -c qemu:///system console node2`. The installer, the
rebased boot and everything after it are on the serial console; the first boot of the installed OS (Ignition and the rebase,
about 40 s) is not, because the kernel argument only takes effect after the rebase's reboot. Without ZFS the installed OS gets no
serial console from this variable.

### Stop

```sh
dev/down.sh            # stop matchbox/dnsmasq, restore host dnsmasq@qemu0
dev/down.sh --destroy  # also delete the VMs
```

### Installing ArgoCD

```sh
K="kubectl --kubeconfig infra/clusters/dev/dev.conf"
# infra/clusters/dev/argocd is infra/system/argocd with the catalogs set to render the dev overlays (cluster=dev)
$K apply --server-side --force-conflicts -k infra/clusters/dev/argocd
$K apply --server-side --force-conflicts -k infra/clusters/dev/argocd   # second pass, see below
```

The first pass installs the CRDs but fails on the `AppProject`/`Application`
resources (CRDs not yet established); the second pass creates the `system`
project and the `root` and `system-catalog` Applications. The apps have no
automated sync policy and track GitHub `HEAD`, so they show `OutOfSync` until
synced manually (and only see what is pushed).

## Developing and testing cluster features

For agents and humans working on charts, manifests and cluster config.

### Reprovision or just apply?

Reprovisioning (`dev/up.sh`, 4-5 minutes) rebuilds the nodes from scratch. Most
work does not need it. Pick by what the change touches:

| Change | Do |
|---|---|
| Kubernetes version, Typhoon ref, `os_version`, CNI, pod/service CIDRs, node count, `install_disk` (`dev.tf`) | **Reprovision** |
| Butane snippets, node-to-MAC pairing, `/etc/hosts` (`infra/clusters/butane`, `dev/butane`) | **Reprovision** |
| matchbox groups/profiles/ignition, PXE/DHCP config (`dev/dnsmasq.conf`, `build/bootstrap`) | **Reprovision** |
| VM hardware or MACs (`dev/vm.sh`) | **Reprovision** |
| Anything that may have broken the cluster (CNI experiments, wiping nodes) | **Reprovision** to get back to a clean state |
| Charts (`charts/`), kustomize apps (`infra/k8s`, `infra/system`), catalog templates, namespaces, NetworkPolicies, operators and CRDs | **No reprovision**: `kubectl apply` or `helm upgrade --install` |
| ArgoCD itself (`infra/system/argocd`) | **No reprovision**: re-run the two-pass `kubectl apply` |

Why: node-level settings are consumed once, at install or first boot, from
matchbox. Re-running `terraform apply` changes matchbox but does not change
nodes that are already installed. Everything inside Kubernetes can be changed
in place.

Test applications with `kubectl`/`helm` first. ArgoCD only syncs from GitHub
`HEAD`, so use it for a change only after it is pushed.

**A node reboot is a reprovision.** `wipe-root.yaml` wipes the root filesystem
on boot, so rebooting or resetting a VM rebuilds the cluster and removes
everything in it, including ArgoCD. Avoid `virsh reset`/`reboot` on a cluster
you want to keep.

**Get a cluster.** Run `dev/up.sh`. Skip it if `kubectl --kubeconfig infra/clusters/dev/dev.conf get nodes` already works.

**Always pass `--kubeconfig` (and `--kube-context` for helm if needed) explicitly.**
`.env` exports `KUBECONFIG` pointing at the real cluster (segv). `dev/up.sh` unsets
it, but your shell may not. Never rely on the environment:

```sh
K="kubectl --kubeconfig infra/clusters/dev/dev.conf"
$K get nodes
helm --kubeconfig infra/clusters/dev/dev.conf ...
```

**Validate locally** (no cluster needed unless noted):

```sh
kubectl kustomize infra/system/argocd           # fetches the upstream install.yaml
helm lint charts/<chart>
helm template <name> charts/<chart> -f <values>
$K apply --dry-run=server -f <manifest>          # validated by the dev API server
```

**Iterate on a chart.** ArgoCD syncs from GitHub `HEAD`, so local edits never flow
through it. Install straight into dev instead:

```sh
helm --kubeconfig infra/clusters/dev/dev.conf upgrade --install <name> charts/<chart> -n <ns> --create-namespace -f <values>
```

or `$K apply -k <kustomize dir>`. Only push once it works in dev.

**Troubleshooting**

* Nodes never come up / stuck at iPXE: `docker compose -f dev/docker-compose.yml logs -f proxydhcp matchbox`
  (look for DHCP requests from 52:54:00:a1:9c:ae / 52:54:00:b2:2f:86 and `/ipxe` hits).
  Check `ip -br a show qemu0` has `10.2.0.1/24`, then `docker compose -f dev/docker-compose.yml restart proxydhcp`
  and `sudo virsh -c qemu:///system reset node1` (same for node2). `dev/up.sh` does this automatically.
* Console: `sudo virsh -c qemu:///system console node1` (exit with `Ctrl+]`).
* SSH: `ssh core@10.2.0.101` (node1), `ssh core@10.2.0.102` (node2). Host keys change on every reprovision
  (`ssh-keygen -R <ip>`; `dev/up.sh` does this).
* Pods: `$K get pods -A`, `$K describe`, `$K logs`.
* `dnsmasq@qemu0` on the host must not run while the dev stack does (`dev/up.sh` handles it).

**Reset.** Run `dev/up.sh` again; it wipes VMs and terraform state and rebuilds.

Keep node MACs and IPs in sync across `dev/vm.sh`, `dev/dnsmasq.conf`,
`infra/clusters/dev/dev.tf` and `infra/clusters/dev/butane/hosts.yaml`.


### Networking (Cilium)

Cilium provides the CNI, kube-proxy replacement, host firewall, WireGuard encryption and the Gateway API
(`GatewayClass cilium`). LoadBalancer IPs come from `CiliumLoadBalancerIPPool` `lan` (10.2.0.200-209 in dev) and are
announced over ARP. To try the gateway with a test app:

```sh
K="kubectl --kubeconfig infra/clusters/dev/dev.conf"
$K apply -f dev/manifests/httpbin.yaml                      # creates the demo namespace
$K apply -k infra/system/cilium/policies/overlays/dev
$K apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml
$K -n cert-manager rollout status deploy/cert-manager-webhook
$K create ns argocd                                         # or install ArgoCD first; the argocd route needs the namespace
$K apply -k infra/k8s/gateway/overlays/dev                  # dev self-signed issuer, Gateway at 10.2.0.200 (retry once if the cert-manager webhook is not reachable yet)
curl -k --resolve httpbin.segfault.me:443:10.2.0.200 https://httpbin.segfault.me/get
```

Host policies default-deny node ingress. Before changing them, put the host endpoint in audit mode so nothing locks you out:
`kubectl -n kube-system exec ds/cilium -- cilium-dbg endpoint config <host endpoint id> PolicyAuditMode=Enabled`
(`cilium-dbg endpoint list` shows the id of the `reserved:host` endpoint).
