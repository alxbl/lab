# Calico Configuration

This is the cluster's Calico configuration and base (global) network policies.

- Assumes Calico is running and configured
- Assumes Calico API Server is present
- Disables Failsafe Network Policies
- Assumes static IP addresses for Controller Nodes

## Host Network Policies

These policies apply at the host level.

### Ingress

- All nodes allow `tcp/22:ssh` and `tcp/179:bgp`
- Controllers additionally allow `tcp/6443:kubeapi`
- Controllers accept `tcp/2279-2280:etcd` between themselves
- All `ClusterIP` services traffic is accepted
  - Individual workloads configure additional policies as needed
  - Only gateway workloads can accept `tcp/80:http` and `tcp/443:https`

  

### Egress

- All nodes allow `udp/53:dns` and `tcp/53:dns-tcp`
- All nodes allow `udp/67:dhcp`
- All nodes allow `tcp/80:http` and `tcp/443:https`

## Internal

These policies apply at the namespace/pod level.

### Ingress

### Egress

