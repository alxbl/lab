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

# Serial console for the PXE installer and the installed OS, e.g. "ttyS1" (TF_VAR_console). The DL380p iLO serial port
# has to be confirmed first; empty disables it.
variable "console" {
  type    = string
  default = ""
}

locals {
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

  # The OS disk is a USB device: /dev/sda is not stable in the installer and could be a pool disk.
  install_disk = "/dev/disk/by-id/scsi-3500014a000000001"
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
    "tachyon" = [
      # Wipe root file system so that reprovisioning is easy
      file("../butane/wipe-root.yaml"),
      file("./butane/hosts.yaml"),
      replace(replace(file("../butane/zfs.yaml"), "@ZFS_IMAGE@", var.zfs_image), "@CONSOLE_KARGS@", local.console_kargs),
    ]
  }
}

resource "local_file" "kubeconfig-segv" {
  content  = module.segv.kubeconfig-admin
  filename = "${path.module}/kube.conf"
  file_permission = "0600"
}
