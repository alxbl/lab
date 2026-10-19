# Raspberry Pi 4 Network Boot Assets

This directory contains the EDK2 UEFI firmware and Raspberry Pi 4 (Model B) files to
network boot into iPXE and Matchbox.

The flow is as follows:

```
- RPI boots into firmware, next boot mode is NET

<RPI NET BOOT>
- Firmware performs DHCP request for net boot as client_arch == 11
- proxyDHCP replies that it supports net boot
- Firmware requests <mac>/pieeprom.sig (TFTP_PREFIX=2);
    if present, pieeprom.upd is downloaded, validated and installed.
    if valid and changed, firmware reboots after EEPROM update
- Firmware requests <mac>/ (a link to rpi4/) files over TFTP
    config.txt
    start4.elf
    ...
- Firmware seeds EFISTUB in config.txt and requests RPI_FD.efi over TFTP
- Firmware boots into RPI_FD.efi

<UEFI PXE Net Boot>
- RPI_FD initializes PXE and gets an IP from DHCP
- RPI_FD sends DHCP boot request and identifies as EFI firmware
- proxyDHCP replies with ipxe-arm64.efi as boot program
- RPI_FD downloads ipxe-arm64.efi over TFTP
- RPI_FD launches ipxe-arm64.efi

<iPXE Net Boot>
- iPXE initializes and gets an IP from DHCP
- iPXE sends DHCP boot request and identifies as iPXE
- proxyDHCP responds with matchbox URL and boot script
- iPXE fetches boot.ipxe from matchbox and runs it
- boot.pixe probes matchbox profile resolution endpoint with mac and uuid
- matchbox serves the right kernel info and ignition url
- iPXE downloads kernel image and initramfs
- iPXE boots into kernel with arguments provided by matchbox

<Ignition>
- At this point, the OS boots and initramfs fetches ignition script
- First boot runs, partitions the disks, sets up and persists the operating system
  - SSH keys, users, additional packages, services, etc.
- Reboot

<Install (install-arm64 profile)>
- The live Ignition config runs rpi4-install, which installs FCOS on /dev/sda,
  then copies the Pi firmware and RPI_EFI.fd (served from this directory by
  matchbox at /assets/rpi4/) onto the new ESP, and reboots

<OS Boot>
- RPI boots from newly provisioned OS on disk (USB)
```
This makes it possible to boot and provision RPIs without ever needing
an SD card, as long as they have an attached disk over USB

## Requirements

- Properly configured proxyDHCP server to serve the right boot files
  - See [/build/bootstrap/dnsmasq.conf](/build/bootstrap/dnsmasq.conf)
- Matchbox must include profiles for the RPI's MAC addresses
- RPI4 EEPROM must be configured to network boot.
  - Recommended boot order is `0xf241` (SD, USB NET, REBOOT)


## Usage
> This works best with PoE HATs or built-in PoE.

Run `scripts/rpi-tftp-links` (also done by `scripts/bootstrap.sh`) to create one
directory link per `matchbox/groups/rpi4-*.json`, named after the Pi's MAC address
(lowercase, hyphenated, as `TFTP_PREFIX=2` requests it). A group with
`metadata.serial` also gets a serial-named link, which Pis use until their EEPROM is updated.

A factory Pi 4 does not netboot out of the box, so the EEPROM must be flashed manually.
Setup an SD card to flash new Pis is simple:

1. Download `pieeprom-*.bin` and `recovery.bin` from a raspberrypi/rpi-eeprom release.
2. `scripts/rpi-recovery-image pieeprom.bin recovery.bin rpi4-recovery.img`
3. `dd` the image to a spare SD card or USB stick.
4. Boot the Pi from SD with no other media. 
5. Wait for the green LED to stay on (screen turns green if a monitor is connected)
6. Shut-down the PI, Remove SD card, and rack it.

Flashed RPIs will netboot and install without further handling. 

Once flashed, the EEPROM can be updated on next boot by running
`scripts/rpi-eeprom-build pieeprom.bin` to download an updated `pieeprom.upd`
and `pieeprom.sig` RPIs will update the firmware on their next reboot

The EFI firmware (`RPI_EFI.fd`) is built with `scripts/build-rpi4-uefi`. 
This compiles in the full RAM (without 3 GB limit) and device tree defaults. 
> **NOTE:** A netbooted RPI cannot save UEFI settings. Do not change them through the EDK2 menu.
`config.txt` must load the device tree where the firmware release expects it
(`device_tree_address` equals `PcdFdtBaseAddress`, 0x3e0000 for v1.53), or it overwrites the firmware.

## References

- [Raspberry Pi Boot Order][boot-order]
- [Raspberry Pi Boot Sequence][boot-seq]


[boot-seq]: https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#raspberry-pi-4-and-raspberry-pi-5-boot-flow
[boot-order]: https://www.raspberrypi.com/documentation//computers/raspberry-pi.html#BOOT_ORDER
