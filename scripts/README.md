# Scripts
Helper scripts for my home lab setup. Most scripts have more
documentation in their source, but this README gives an overview.

Scripts used only for the development cluster live in `dev/`, see
[DEVELOPMENT.md](../DEVELOPMENT.md). Tools such as `terraform`, `kubectl`
and `helm` are expected to be installed on the host.

## install-cilium.sh

`install-cilium.sh [--nodes N] <kubeconfig> <cluster>` installs the Gateway API CRDs and Cilium
(chart version from the system catalog, values from `infra/system/cilium`) on a cluster whose nodes
have no CNI yet. Used by `dev/up.sh` and the segv bootstrap; ArgoCD adopts the Helm release.

## bootstrap.sh

**Legacy**: not used for segv any more (see README.md "Usage"). It stops DNS services and edits iptables.

Bootstraps the production cluster: starts matchbox and the proxyDHCP
server, runs `terraform apply` for `infra/clusters/segv`, then tears
everything down. See the top-level README for requirements.

## arr-backup

Runs the Backup command of Sonarr, Radarr and Prowlarr in the `aquisition`
pod on segv, copies the zips to a local directory (default `./arr-backups`)
and checks each database with `sqlite3`. Run it before arr major bumps.
With `--keep N`, manual backups in the pod beyond the N newest (the new
one included) are deleted after the new one verifies; otherwise none are pruned.

## bootstrap-pki

Generates a throwaway CA, server and client certificates under `/pki`
for talking to matchbox during bootstrapping.

## get-fedora-coreos

Downloads the Fedora CoreOS PXE assets into the matchbox assets
directory (`build/bootstrap/matchbox/assets`). Pass the architecture as the
fourth argument, e.g. `get-fedora-coreos stable "" "" aarch64` for the Pi 4.

## rpi-eeprom-build

Builds `pieeprom.upd` and `pieeprom.sig` from `build/bootstrap/rpi4/boot.conf`
and a stock `pieeprom.bin`, into the TFTP directory served to Raspberry Pi 4
nodes. Requires `rpi-eeprom-config`.

## rpi-recovery-image

Builds a FAT image that flashes the Pi 4 EEPROM config (`rpi-eeprom-build`
output plus `recovery.bin`). Run it once, `dd` the image to an SD card or USB
stick, and use that media to prepare each Pi before it is racked. Requires
`mkfs.vfat` and `mcopy`.

## build-rpi4-uefi

Builds the pftf/RPi4 EDK2 firmware (`RPI_EFI.fd`) in a container, with full RAM
and device tree as defaults (`rpi4-uefi-defaults`). Netbooted Pis cannot save UEFI
settings, so the defaults must be compiled in. Needs docker or podman.

## rpi-tftp-links

Links `build/bootstrap/tftp/<mac>` to `tftp/rpi4` for every `rpi4-*.json`
matchbox group. Run by `bootstrap.sh`.

## export-secrets / import-secrets

**Require `proton-drive`, logged in**

`export-secrets <kubeconfig>` copies the Secrets listed in `scripts/secrets.list`
from a cluster to Proton Drive (`/my-files/Documents/Homelab/_secrets/<cluster>/manifests`),
stripping cluster-specific metadata. `import-secrets [--dry-run] <kubeconfig> [namespace...]`
applies them to a cluster, creating missing namespaces.

## import-certs

**Requires `proton-drive`, logged in**

This copies the relevant public certificates from Proton Drive into `/pki` of the
repository and is required for some of the bootstrapping code that uses certificates.

For privacy reasons, only my root level CA is committed.


## pacstrap.sh

`pacstrap.sh` is used to bootstrap a brand new Arch Linux install on a
workstation.

> **NOTE**: This script must stay at `scripts/pacstrap.sh`. A shortened
> URL (`bit.ly/pacstrap`) points to it.

This is useful when reformatting a laptop or a desktop computer which usually
runs Linux.

### Usage

`curl -sSfL https://bit.ly/pacstrap | HOST=hostname sh` to go from a brand new
machine with no OS on it to a fully partitioned, configured, and running
machine.

Keep in mind that these scripts have been tailored specifically to my needs and
that the pacstrap portion of it assumes that it is fine to wipe the harddrives
clean. **Do not run this without reading through the scripts first.**

There are two parts to this project wrapped in a single command line:

### 1. Bootstrap a machine from Arch Linux Live USB

This part deals with everything up to `pacstrap /mnt base base-devel`,
including custom partition tables per host (`pacstrap.d/<hostname>.sh`) and
setting up ansible for the next steps. The only concerns here are configuring
the base system so that ansible can work and run on it.  Once that is done,
everything else is handled by Ansible itself.

### 2. Ansible Pull

This part does the actual configuration management, package installation and
setting up of the system, using the playbook in `ansible/`.
