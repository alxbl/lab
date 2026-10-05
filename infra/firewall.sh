# These rules are required for local development (on firewalled hypervisor) to work
#
# PODMAN : Allow all egress and DNS
#
# Accept DNS traffic
-A INPUT -i podman1 -p udp -m udp -m multiport --dports 53 -j ACCEPT
-A INPUT -i podman1 -p tcp -m tcp -m multiport --dports 53 -j ACCEPT

# Allow established traffic for the hypervisor subnet
#-A FORWARD -d 10.2.0.0/24 -o qemu0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
# -- OR --
# Allow any forwarded traffic through (enables port forwarding)
-A FORWARD -d 10.89.0.0/24 -o podman1 -j ACCEPT

# Allow outbound traffic from the subnet to be forwarded
-A FORWARD -s 10.89.0.0/24 -i podman1 -j ACCEPT
# Allow all traffic within the subnet through
-A FORWARD -i podman1 -o podman1 -j ACCEPT
# Reject everything else with ICMP unreachable
-A FORWARD -i podman1 -j REJECT --reject-with icmp-port-unreachable
-A FORWARD -o podman1 -j REJECT --reject-with icmp-port-unreachable

