# Homelab Infra-as-Code / GitOps

This repository hosts my infra-as-code and gitops configurations for my home network.
It also contains various bootstrapping scripts for workstations and servers alike.


## Workstation Bootstrapping
Workstations running ArchLinux (btw) are provisioned via `scripts/pacstrap.sh`

```sh
# After booting into ArchLinux Live USB
# alternatively: https://raw.githubusercontent.com/alxbl/lab/main/scripts/pacstrap.sh
curl -sSfL https://bit.ly/pacstrap | HOST=hostname sh`
```

## Cluster Bootstrapping

Once the cluster is bootstrapped, it is self-sufficient as long as there is at least one controller node
up and running. Bootstrapping is only necessary in case a full recovery is necessary after simultaneous
failure of all nodes.

**Bootstrapping Synthetic Test Status**: `Not implemented`


### Requirements

The following requirements must be met for bootstrapping to work:

These tools must be available on the OS: 

- docker
- docker-compose
- nodejs and npm > 12
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

```
TODO
```

Additionally, set `LAB_SECRETS_PARTUUID` in `/.env` to the partition UUID of the secrets drive for automounting
to work as expected:

```sh
lsblk -o NAME,UUID /dev/sda1
```


### Usage

- Ensure the requirements are met
- Plug the secrets removable media in a port 
- (TODO) Update `cluster.json` to specify the MAC address of the machines that are to be part ofthe cluster
- Run `scripts/bootstrap.sh`
- When prompted, power on the machines so that they network boot
- Grab a coffee and wait.


Bootstrapping must provision at least one controller node. The cluster is bootstrapped to be able to provision
new nodes as necessary, so nodes can be dynamically added without running the bootstrap script again.


