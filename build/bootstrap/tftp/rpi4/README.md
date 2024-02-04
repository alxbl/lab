# Raspberry Pi 4 Network Boot Assets

This directory conains the EDK2 UEFI firmware and Raspberry Pi 4 (Model B) files to
network boot into iPXE and Matchbox.

The flow is as follows:

```
- RPI boots into firmware, next boot mode is NET

<RPI NET BOOT>
- Firmware performs DHCP request for net boot as client_arch == 11
- proxyDHCP replies that it supports net boot
- Firmware requests pieeprom.sig; 
    if present, pieeprom.upd is downloaded, validated and installed.
    if valid and changed, firmware reboots after EEPROM update
- Firmware requests rpi4/ files over TFTP
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
Create a symlink from the Pi's Serial Number (last 8 characters) to this
directory.

```sh
ln -s rpi4 aabbccdd
```

Update the EEPROM so that NET boot is enabled (TODO: instructions)

## References
- [Raspberry Pi Boot Order][boot-order]
- [Raspberry Pi Boot Sequence][boot-seq]


[boot-seq]: https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#raspberry-pi-4-and-raspberry-pi-5-boot-flow
[boot-order]: https://www.raspberrypi.com/documentation//computers/raspberry-pi.html#BOOT_ORDER
