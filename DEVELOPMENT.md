# Development Setup

> **Disclaimer**: A lot of this makes assumptions about my own setup,
> so it will most likely not work out of the box if you are not using
> my configurations and environment.

## Assumptions

* Hypervisor setup with QEMU and KVM
* `qemu0` bridge exists
* Host is runing a recent enough version of Linux with all required
  tools intalled

## Development Cluster

> **NOTE**: The dev cluster does not add ZFS support or rebase to
> `ghcr.io/alxbl/lab/fcos` for the time being as that is not necessary
> for development.

The purpose of this is to be able to iterate and test the
bootstrapping process quickly without having to deal with hardware.

It takes about 5-6 minutes to wipe the devnet VMs and reprovision the
cluster from scratch:

```sh
pwd # $HOME/Code/github.com/alxbl/lab
source .env
cd scripts/

# Stop qemu0 bridge DNSmasq if it's running
sudo systemctl stop dnsmasq@qemu0

# Download FCOS images if necessary
# Start PXE server and matchbox
docker-compose -f ../build/bootstrap/devnet.yml up -d

# Cycle the disks and VMs
sudo ./vm.sh destroy && ./vm.sh create

# Bootstrap the cluster using terraform
cd ../infra/clusters/dev
terraform apply

# This might be necessary if nothing else is running on qemu0 since 
# the iface will be down and dnsmasq won't be bound to it, causing
# iPXE to fail to boot.
sudo virsh reset node1
sudo virsh reset node2
```

To go a step further, it's possible to actually launch the full
cluster provisioning, but this might not scale.

```sh
REPO_ROOT=$HOME/Code/github.com/alxbl/lab
cd $REPO_ROOT
export KUBECONFIG=$REPO_ROOT/infra/clusters/dev/kube.conf
kubectl apply -k $REPO_ROOT/infra/k8s/argocd
```

This will deploy ArgoCD and the `root` application, which follows the
[app-of-apps][argocd-apps] pattern to provision and configure
everything else in the cluster.

[argocd-apps]: https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/#app-of-apps-pattern
