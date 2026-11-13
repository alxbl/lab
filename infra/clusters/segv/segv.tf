# This is a wrapper around the Typhoon module so that it can be invoked via CDKTF eventually.
provider "matchbox" {
  endpoint    = "127.0.0.1:8081"
  client_cert = file("${path.module}/../../../pki/client.crt")
  client_key  = file("${path.module}/../../../pki/client.key")
  ca          = file("${path.module}/../../../pki/ca.crt")
}

provider "ct" {}

terraform {
  required_providers {
    ct = {
      source  = "poseidon/ct"
      version = "0.14.0"
    }
    matchbox = {
      source = "poseidon/matchbox"
      version = "0.5.2"
    }
  }
}

# The node boots stock Fedora CoreOS from PXE and rebases once onto this image, which adds ZFS
# (infra/clusters/butane/zfs.yaml). Pinned by digest because `latest` is rebuilt weekly.
# Fallback if this image misbehaves: the 2024 image the node ran before, ghcr.io/alxbl/lab/fcos@sha256:e7e4fe5c0f7b15cacdb8c6e379819de484649f4b17a452d5523df286cb28a241
variable "zfs_image" {
  type    = string
  default = "ghcr.io/alxbl/lab/fcos@sha256:c3f66a675424002b2c980891a13b820f4ce5500c4c0f407995b4870bc17616e1"
}

# Serial console for the PXE installer and the installed OS (TF_VAR_console overrides, empty disables it).
# ttyS1 (COM2) is the DL380p iLO virtual serial port: verified by writing to both UARTs while attached to Serial-over-LAN
# (only ttyS1 arrived). iLO's SOL speed is 115.2 kbps. The BIOS itself does not redirect its console (ACPI SPCR is empty).
variable "console" {
  type    = string
  default = "ttyS1"
}

# Stable /dev/disk/by-id path of the NVMe disk that holds the OS root, /var/lib/etcd and /var/lib/containerd
# (infra/clusters/butane/nvme-disk.yaml); the USB install disk then keeps only the bootloader, the ESP and /boot.
# Empty keeps everything on the USB disk (wipe-root.yaml), the layout before the move.
variable "nvme_disk" {
  type    = string
  default = "/dev/disk/by-id/nvme-Patriot_M.2_P320_256GB_P320ECBB25122302234"
}

locals {
  # The OS disk is a USB device: /dev/sda is not stable in the installer and could be a pool disk.
  os_disk       = "/dev/disk/by-id/scsi-3500014a000000001"
  console_args  = var.console == "" ? [] : ["console=tty0", "console=${var.console},115200n8"]
  console_kargs = var.console == "" ? "" : "ExecStart=/usr/bin/rpm-ostree kargs ${join(" ", [for a in local.console_args : "--append-if-missing=${a}"])}"
}

module "segv" {
  source = "git::https://github.com/poseidon/typhoon//bare-metal/fedora-coreos/kubernetes?ref=97ee4103eb27777c0d2411ef1a5c761f3d3ee462"

  # bare-metal
  cluster_name            = "segv"
  matchbox_http_endpoint  = "http://matchbox.lan:8080"
  os_stream               = "stable"
  # Installer only: the OS that runs comes from zfs_image.
  os_version              = "44.20260913.3.2"

  # configuration
  k8s_domain_name    = "tachyon.lan"
  ssh_authorized_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO+M9LUT9LQWQFTxz7SR2jXhxyZs6rS5CLN2aFS6HMB5"

  install_disk = local.os_disk
  kernel_args  = local.console_args
  cached_install = true

  networking = "cilium"

  # Cilium (and the Gateway API CRDs) are installed with scripts/install-cilium.sh, then adopted by ArgoCD.
  components = {
    cilium = { enable = false }
  }

  controllers = [
    {
      name = "tachyon",
      mac = "ac:16:2d:a7:ae:90",
      domain = "tachyon.lan"
    }
  ]

  # workers = []

  snippets = {
    "tachyon" = concat([
      file("./butane/hosts.yaml"),
      file("../butane/sysctl.yaml"),
      file("../butane/kubelet.yaml"),
      replace(replace(file("../butane/zfs.yaml"), "@ZFS_IMAGE@", var.zfs_image), "@CONSOLE_KARGS@", local.console_kargs),
    ], var.nvme_disk == "" ?
      # Wipe root file system so that reprovisioning is easy
      [file("../butane/wipe-root.yaml")] :
      # The root filesystem is wiped (recreated) on the NVMe, see the snippet.
      [replace(replace(file("../butane/nvme-disk.yaml"), "@NVME_DISK@", var.nvme_disk), "@OS_DISK@", local.os_disk)]
    )
  }
}

resource "local_file" "kubeconfig-segv" {
  content  = module.segv.kubeconfig-admin
  filename = "${path.module}/kube.conf"
  file_permission = "0600"
}
