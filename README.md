# Configuration and Bootstrapping Framework

`curl -sSf https://.../pacstrap.sh | HOST=hostname sh` to go from a brand new
machine with no OS on it to a fully partitioned, configured, and running
machine.

Keep in mind that these scripts have been tailored specifically to my needs and
that the pacstrap portion of it assumes that it is fine to wipe the harddrives
clean. **Do not run this without reading through the scripts first.**

There are two parts to this project wrapped in a single command line:

## 1. Bootstrap a machine from Arch Linux Live USB

This part deals with everything up to `pacstrap /mnt base base-devel`,
including custom partition tables per host and setting up ansible for the next
steps. The only concerns here are configuring the base system so that ansible
can work and run on it.  Once that is done, everything else is handled by
Ansible itself.

## 2. Ansible Pull

This part does the actual configuration management, package installation and
setting up of the system.

