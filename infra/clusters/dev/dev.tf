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

module "dev" {
  source = "git::https://github.com/alxbl/typhoon//bare-metal/fedora-coreos/kubernetes?ref=u/alxbl/cilium-1.20.2"

  # bare-metal
  cluster_name            = "dev"
  matchbox_http_endpoint  = "http://10.2.0.1:8080"
  os_stream               = "stable"
  os_version              = "44.20260913.3.2"

  # configuration
  k8s_domain_name    = "node1"
  ssh_authorized_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO+M9LUT9LQWQFTxz7SR2jXhxyZs6rS5CLN2aFS6HMB5"

  install_disk = "/dev/vda"
  cached_install = true

  # Avoid clashing with qemu0 stuff.
  pod_cidr = "10.22.0.0/16"
  service_cidr = "10.33.0.0/16"
  networking = "cilium"

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

  # Setup static DNS in /etc/hosts so that routing works properly.
  snippets = {
    "node1" = [ file("../butane/wipe-root.yaml"), file("./butane/hosts.yaml") ]
    "node2" = [ file("../butane/wipe-root.yaml"), file("./butane/hosts.yaml") ]
  }
}

resource "local_file" "kubeconfig-dev" {
  content  = module.dev.kubeconfig-admin
  filename = "${path.module}/dev.conf"
  file_permission = "0600"
}
