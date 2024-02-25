#!/usr/bin/env bash
# Manage VM nodes which have a specific set of hardware attributes.
# Adapted from: https://github.com/poseidon/matchbox/blob/main/scripts/devnet
# Modifications:
#   - Use qemu0 interface as bridge
#   - Possibility to use a non-default disk pool.

VM_MEMORY=${VM_MEMORY:-3048}
VM_DISK=${VM_DISK:-10}
VM_BRIDGE=qemu0
VM_POOL=disks

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

function main {
  case "$1" in
    "create") create_docker;;
    "start") start;;
    "reboot") reboot;;
    "shutdown") shutdown;;
    "poweroff") poweroff;;
    "destroy") destroy;;
    *)
      usage
      exit 2
      ;;
  esac
}

function usage {
  echo "USAGE: ${0##*/} <command>"
  echo "Commands:"
  echo -e "\tcreate\t\tcreate QEMU/KVM nodes on the $VM_BRIDGE bridge"
  echo -e "\tstart\t\tstart the QEMU/KVM nodes"
  echo -e "\treboot\t\treboot the QEMU/KVM nodes"
  echo -e "\tshutdown\tshutdown the QEMU/KVM nodes"
  echo -e "\tpoweroff\tpoweroff the QEMU/KVM nodes"
  echo -e "\tdestroy\t\tdestroy the QEMU/KVM nodes"
}

# --install=no_install=yes is a workaround for a virt-manager 4.1.0 regression
# https://github.com/virt-manager/virt-manager/issues/426
COMMON_VIRT_OPTS="--memory=${VM_MEMORY} --vcpus=2 --disk pool=$VM_POOL,size=${VM_DISK} --os-variant=fedora-coreos-stable --noautoconsole --install=no_install=yes"

NODE1_NAME=node1
NODE1_MAC=52:54:00:a1:9c:ae

NODE2_NAME=node2
NODE2_MAC=52:54:00:b2:2f:86

NODE3_NAME=node3
NODE3_MAC=52:54:00:c3:61:77

function create_docker {
  virt-install --name $NODE1_NAME --network=bridge:$VM_BRIDGE,mac=$NODE1_MAC $COMMON_VIRT_OPTS --boot=network
  virt-install --name $NODE2_NAME --network=bridge:$VM_BRIDGE,mac=$NODE2_MAC $COMMON_VIRT_OPTS --boot=network
  # virt-install --name $NODE3_NAME --network=bridge:$VM_BRIDGE,mac=$NODE3_MAC $COMMON_VIRT_OPTS --boot=hd,network
}

nodes=(node1 node2)

function start {
  for node in ${nodes[@]}; do
    virsh start $node
  done
}

function reboot {
  for node in ${nodes[@]}; do
    virsh reboot $node
  done
}

function shutdown {
  for node in ${nodes[@]}; do
    virsh shutdown $node
  done
}

function poweroff {
  for node in ${nodes[@]}; do
    virsh destroy $node
  done
}

function destroy {
  for node in ${nodes[@]}; do
    virsh destroy $node
  done
  for node in ${nodes[@]}; do
    virsh undefine $node
  done
  virsh pool-refresh $VM_POOL
  for node in ${nodes[@]}; do
    virsh vol-delete --pool $VM_POOL $node.qcow2
  done
}

main $@
