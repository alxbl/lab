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
      version = "0.13.0"
    }
    matchbox = {
      source = "poseidon/matchbox"
      version = "0.5.2"
    }
  }
}

module "segv" {
  source = "git::https://github.com/alxbl/typhoon//bare-metal/fedora-coreos/kubernetes?ref=alxbl/aarch64"

  # bare-metal
  cluster_name            = "segv"
  matchbox_http_endpoint  = "http://th1nk.lan:8080"
  os_stream               = "stable"
  os_version              = "39.20240112.3.0"

  # configuration
  k8s_domain_name    = "tachyon.lan"
  ssh_authorized_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO+M9LUT9LQWQFTxz7SR2jXhxyZs6rS5CLN2aFS6HMB5"

  install_disk = "/dev/sda"
  cached_install = true

  controllers = [
    {
      name = "tachyon",
      mac = "ac:16:2d:a7:ae:90",
      domain = "tachyon.lan"
    }
  ]

  # workers = []
}

resource "local_file" "kubeconfig-segv" {
  content  = module.segv.kubeconfig-admin
  # FIXME: Write to $HOME or to /mnt/secrets
  filename = "/home/dom0/.kube/configs/segv.conf"
  file_permission = "0600"
}
