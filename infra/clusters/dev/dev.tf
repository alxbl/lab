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

module "dev" {
  source = "git::https://github.com/alxbl/typhoon//bare-metal/fedora-coreos/kubernetes?ref=alxbl/aarch64"

  # bare-metal
  cluster_name            = "dev"
  matchbox_http_endpoint  = "http://10.2.0.1:8080"
  os_stream               = "stable"
  os_version              = "39.20240112.3.0"

  # configuration
  k8s_domain_name    = "node1"
  ssh_authorized_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO+M9LUT9LQWQFTxz7SR2jXhxyZs6rS5CLN2aFS6HMB5"

  install_disk = "/dev/vda"
  cached_install = true

  controllers = [
    {
      name = "node1",
      mac = "52:54:00:a1:9c:ae",
      domain = "node1"
    }
  ]

  workers = [
    {
        name = "node2",
        mac = "52:54:00:b2:2f:86",
        domain = "node2",
        arch = "x86_64"
    }
  ]
}

resource "local_file" "kubeconfig-dev" {
  content  = module.dev.kubeconfig-admin
  # FIXME: Write to $HOME or to /mnt/secrets
  filename = "${path.module}/kube.conf"
  file_permission = "0600"
}
