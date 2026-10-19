# Scripts
Helper scripts for my home lab setup. Most scripts have more
documentation in their source, but this README gives an overview.

Scripts used only for the development cluster live in `dev/`, see
[DEVELOPMENT.md](../DEVELOPMENT.md). Tools such as `terraform`, `kubectl`
and `helm` are expected to be installed on the host.

## bootstrap.sh

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
directory (`build/bootstrap/matchbox/assets`).

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
