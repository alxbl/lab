# aquisition

> **WARNING**: `aquisition` requires Kubernetes 1.29 or more recent > for SideCar init
> containers to prevent VPN leaks. Alternatively, you can enable the
> [`SidecarContainers`][1] feature gate on older versions at your own risk.

A helm chart that deploys a "media aquisition"  workload in
a Kubernetes cluster using [`gluetun`][gluetun] to provide a leak-proof VPN.

Valid VPN subscription required. Supports NAT+PMP and port-forwarding.

aquisition deploys the following software:

- Sonarr
- Radarr
- Prowlarr
- rtorrent
- gluetun (SideCar)

## Compatible VPNs

VPN support is provided through the excellent [`gluetun`][gluetun]. Look at its
documentation.

## Customizing Values

TODO

## Feature List

- [ ] Port Forwarding (NAT-PMP)
- [ ] VPN over SOCKS Proxy
- [X] Firewall prevent leaks from pod (gluetun)
- [ ] istio compatibility (currently: side-car opt-out)
- [ ] Network Policies on top of firewall (defense-in-depth).

## Support

These are my personal configuration files, and as such, support is on a best effort basis.
This documentation acts as my personal notes and can hopefully help others, but the
intended audience is people with a strong technical background.

[1]: https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/#enabling-sidecar-containers
[gluetun]: https://github.com/qdm12/gluetun
