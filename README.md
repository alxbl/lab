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
curl -sSfL https://bit.ly/pacstrap | HOST=hostname sh`
```

## Cluster Overview

Each node is running Fedora Core OS with an additional layer (via
`rpm-ostree rebase`) which includes ZFS drivers and userland utilities
as well as my fork of Typhoon.

Currently, my homelab cluster is made up of the following nodes:

- HP Proliant D630p G8 (2x 2.5GHz Xeon / 256GB RAM)
  - OS Drive: 500GB external SSD (`/`)
  - Data Pool: 8x1.2TB HDDs in a ZFS Raidz2 configuation (`/var/data`)

The high level diagram [can be found here](#TODO)

## Cluster Bootstrapping

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

Additionally, the user running the bootstrap script must be a `sudoer` (without password for maximum automation)

Lastly, a removable media containing secrets must be plugged in the computer.
`bootstrap.sh` will take care of mounting it and unmounting it as needed.

### Secrets Drive Structure

> **NOTE**: Currently, the secrets drive is not encrypted. This is a future improvement.

In the interest of reproducibility, here is the overall structure that the secrets drive must have:

```plain
TODO
```

Additionally, set `LAB_SECRETS_PARTUUID` in `/.env` to the partition UUID of the secrets drive for automounting
to work as expected:

```sh
lsblk -o NAME,UUID /dev/sda1
# NAME      UUID
# sda1 AB1C-999D
```

### Usage

- Ensure the requirements are met
- Plug the secrets removable media in a port
- Run `scripts/bootstrap.sh`
- When prompted, power on the machines so that they network boot
- Grab a coffee and wait

terraform will report that it is waiting for provisioning as such:

```plain
segv  module.typhoon-module.null_resource.copy-controller-secrets[0]: 
Provisioning with 'file'...
segv  module.typhoon-module.null_resource.copy-controller-secrets[0]: Still creating... [10s elapsed]
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
