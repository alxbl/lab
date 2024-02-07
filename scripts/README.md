# Scripts
Various helper scripts for my home lab setup. Most scripts have more
documentation in their source, but this README gives an overview.

## `bin/` scripts

Everything under `bin/` is either a tool or a wrapper around a tool that I do
not want to require on the host operating system.

Wrappers will usually invoke a docker with an ephemeral container (`--rm`) and
pass arguments to the container, mapping the current directory to make
execution seamless.

## get-terraform

Downloads the terraform binary from HashiCorp and places it where it will be
available for the repository.

## import-certs

**Requires secrets drive**

This copies the relevant public certificates into `/pki` of the repository and
is required for some of the bootstrapping code that uses certificates.

For privacy reasons, only my root level CA is committed, the rest of the PKI is
stored offline

## pacstrap.sh

`pacstrap.sh` is used to bootstrap a brand new Arch Linux install on a
workstation.

This is useful when reformatting a laptop or a desktop computer which usually
runs Linux.

### Usage

`curl -sSf https://.../pacstrap.sh | HOST=hostname sh` to go from a brand new
machine with no OS on it to a fully partitioned, configured, and running
machine.

Keep in mind that these scripts have been tailored specifically to my needs and
that the pacstrap portion of it assumes that it is fine to wipe the harddrives
clean. **Do not run this without reading through the scripts first.**

There are two parts to this project wrapped in a single command line:

### 1. Bootstrap a machine from Arch Linux Live USB

This part deals with everything up to `pacstrap /mnt base base-devel`,
including custom partition tables per host and setting up ansible for the next
steps. The only concerns here are configuring the base system so that ansible
can work and run on it.  Once that is done, everything else is handled by
Ansible itself.

## 2. Ansible Pull

This part does the actual configuration management, package installation and
setting up of the system.

