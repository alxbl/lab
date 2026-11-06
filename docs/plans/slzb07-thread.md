# SLZB-07 as a Thread border router for Home Assistant (Matter over Thread)

Goal: the SLZB-07 (EFR32MG21, USB, CP2102N) runs OpenThread RCP firmware and sits in `tachyon.lan`. A Thread border router (OTBR) pod owns it, a Matter server pod commissions devices, and the `home-assistant` pod uses both.

Conventions: `STOP and ask` = the user says go in the conversation first. Secrets never enter the repo, logs or chat.

## STATUS / RESUME NOTES (2026-11-06) - read first
Done:
- SLZB-07 flashed with OpenThread RCP 2.7.2.0 (921600 baud, RTS/CTS), plugged into tachyon on a USB extension. By-id path as in the manifests. Flash tooling is in the session scratchpad only (venv `usf-venv`, firmware under `fw-nerivec-v2025.6.2-update1/`); `universal-silabs-flasher --bootloader-reset rts_dtr` was needed (`slzb07` method needs a GPIO chip).
- ZFS datasets `data/k8s/otbr` and `data/k8s/matter-server` exist on tachyon (1G, context=none). PR #152 merged: manifests, PVs, catalog apps. `storage`, `root` and `otbr` were synced; **`matter-server` is not synced**.
- Decisions: Thread-only; same namespace `home`; try without routable IPv6 first. Routable IPv6 (prefix, firewall, ingress, Cilium review) is a separate plan, only if everything else is exhausted.

INCIDENT 2026-11-06 (do not repeat): the `openthread/otbr` image entrypoint runs `sysctl --system` (applying the image's Ubuntu sysctls to the host), plus NAT44/NAT64 and firewall scripts, when run `privileged` on `hostNetwork`. It set host `net.ipv4.conf.all.rp_filter=1` (host wants 0, `/etc/sysctl.d/99-zzz-override_cilium.conf`), which broke Cilium: pod-to-API timeouts, crash-looping controllers, DNS outage. Fixed with `sudo sysctl --system` on tachyon; OTBR scaled to 0. Still changed on the host until reboot: `net.ipv6.conf.all.forwarding=1` and `net.ipv6.conf.eno1.accept_ra=0` (originals unknown; harmless while Cilium has IPv6 off).
- **Never scale `otbr` up or re-sync it as written.** After any privileged/host-network workload, verify `sysctl net.ipv4.conf.all.rp_filter` is 0 and DNS (`dig @10.3.0.53 example.com`) works.
- Live drift: the `otbr` Deployment has replicas 0, `NAT64=0` and no hostPath `type` (the kubelet rejects `CharDevice` for the by-id symlink). Git still has `type: CharDevice` (fix on unmerged local branch/worktree `otbr-hostpath`). Re-sync from git before any use.
- Argo apps track `main` on GitHub: nothing deploys until merged.

CURRENT (2026-11-06, option 1 live): `otbr` runs `otbr-agent` directly on the host network (PR #153, #154, #155) with border routing OFF (`ot-ctl br disable` in the postStart hook), BBR and NAT64 off, and the SRP server enabled by hand (`ot-ctl srp server enable`; it auto-enables only with border routing). Verified live 2026-11-06 on the host network: leader, `rp_filter` 0, forwarding 0, DNS fine, HA pod reaches `http://otbr.home.svc:8081/node` and `matter-server.home.svc:5580`; `matter-server` synced and running. A Thread network (dataset in the otbr PVC) already exists. The radio was verified on the real SLZB-07 in a pod-network canary (leader, RCP `SL-OPENTHREAD/2.7.2.0_GitHub-fb0446f53`). No Matter device has been paired yet (the user owns none); the Thread/Matter integrations in Home Assistant are added by hand when one exists. If pairing or control fails, see "Border routing: option 1 (current) vs option 2 vs option 3" and implement option 2 or 3.


## Findings that shape the plan
- The dongle is on this workstation as `/dev/serial/by-id/usb-SMLIGHT_SMLIGHT_SLZB-07_b0e08c1bd5a0ef11bec3a9a361ce3355-if00-port0` (CP210x, `10c4:ea60`). The by-id name is stable across hosts, so the cluster needs no udev rule and **no butane change** (a butane change means a node reprovision).
- tachyon (Fedora CoreOS 7.2.7, SELinux enforcing) ships `cp210x` and `tun` modules. No sysctl or module change is needed for the dongle itself.
- **HA does not talk to the dongle.** The RCP is owned by the border router (OTBR). HA only needs OTBR's REST URL (Thread integration) and the Matter server's websocket (Matter integration). Mounting the device into the HA pod itself would be wrong: HA container has no add-ons, and the Thread integration speaks to an OTBR over HTTP. The device is mounted into the OTBR pod; "exposed to HA" means reachable through the Services below.
- The `home-assistant` Application is the `pajikos` chart (`infra/k8s/catalog/templates/home-assistant.yaml`), namespace `home`, which is already default-deny (`baseline` policy). New pods in `home` need their own NetworkPolicy ports.
- Thread needs link-local IPv6 multicast and mDNS on the LAN. tachyon's `eno1` has only a link-local IPv6 address (10.0.0.6/16 + `fe80::`). The first attempt runs with that alone (see "IPv6 strategy"); routable IPv6 is a fallback plan, not part of this one.
- Host firewall: `host-allow-lan` default-denies LAN ingress to the node (22, 6443, ICMP) and `host-allow-cluster` admits all cluster traffic; `hostNetwork` pods are subject to both, not to namespace NetworkPolicies. Namespace `home` has no Pod Security labels, so privileged host-network pods are admitted.

## Investigation: OTBR without host takeover (2026-11-06)
Method: built OpenThread's simulated RCP (`ot-rcp`, static, from `openthread/openthread` `5b4fb8e` with its pinned mbedtls submodules, in the session scratchpad) and ran the image's own `/usr/sbin/otbr-agent` against it in a rootless podman container with `--network none`, a dummy infra interface, `--cap-drop all` and only the capabilities listed below. Snapshotted sysctls, routes, addresses, iptables/ip6tables before and after forming a Thread network.

Findings (sandbox, simulated radio):
- All host damage came from the image's shell entrypoint (`sysctl --system`, `/etc/sysctl.d/60-otbr-*` forwarding and accept_ra, NAT44/NAT64, firewall/ipset). `otbr-agent` itself needs none of it. Run the binary directly.
- Agent run directly: became Thread leader; border routing, BBR primary and SRP server all running; **no iptables/ip6tables changes, no global sysctl changes**. It only adds wpan0 sysctls, wpan0 addresses/routes, a ULA address and route on the infra interface (its own RA), and sets `net.ipv6.conf.{all,<infra>}.mc_forwarding=1` (backbone-router multicast routing).
- `ot-ctl bbr disable` returns `mc_forwarding` to 0 and the leader, border routing and SRP keep running. `ot-ctl nat64 disable` stops the in-agent NAT64. Neither persists across restarts, hence the postStart hook.
- IPv6 forwarding stays 0 and `accept_ra` untouched; the network still forms. Host forwarding is only needed for LAN clients to reach Thread devices; the Matter server runs on the same host and reaches the mesh through wpan0.
- `otbr-agent` (built with D-Bus) aborts after about 10 failed retries without a system bus: run `dbus-daemon --system` in a sidecar sharing an emptyDir at `/run/dbus` (needs SETUID, SETGID, SETPCAP, CHOWN, DAC_OVERRIDE).
- mDNS: the agent binds UDP 5353 itself (built-in publisher, no avahi). tachyon has nothing on 5353 and avahi is inactive.
- The ipset "protocol version" warning is benign (the sets only exist if the firewall script ran).
- Draft manifest: `infra/k8s/otbr/deployment.yaml` (replicas 0, not deployed, `kubectl apply --dry-run=server` passes).

Caveats / not proven:
- Simulated radio only: the real SLZB-07 (921600 baud, RTS/CTS, `uart-flow-control`) is untested with the agent.
- `privileged: true` is still used for the tty and `/dev/net/tun` (a hostPath char device is blocked by the device cgroup otherwise). The command is ours, so nothing runs sysctl. Hardening option: `squat/generic-device-plugin` exposing the tty and `/dev/net/tun`, then drop privileged.
- Border routing sends RAs on `eno1` advertising its own on-link ULA prefix and an OMR route. LAN hosts may autoconfigure ULA addresses. This is OTBR's own prefix, not routable, but it is IPv6 on the LAN. `ot-ctl br disable` avoids it, at the cost of the mesh being reachable only from tachyon; untested whether the Advertising Proxy then publishes usable addresses for Matter.
- Revert on tachyon is still pending (needs the user's go): `net.ipv6.conf.{all,default,eno1}.forwarding` back to 0 (set to 1 by the old entrypoint) and `net.ipv6.conf.eno1.accept_ra` back to default.

## Border routing: option 1 (current) vs option 2 vs option 3
Why this exists: with border routing ON, `otbr-agent` sends router advertisements on `eno1` carrying its own non-routable ULA on-link prefix and a route to the Thread OMR prefix, so LAN hosts may autoconfigure ULA addresses. The user wanted to try without IPv6 on the LAN first, hence:

**Option 1 (current):** border routing OFF, SRP server enabled manually. The Thread mesh is reachable only from tachyon (`wpan0`); `matter-server` is on the host network on the same node, so it reaches the mesh directly. Unproven: whether Matter commissioning and operation work this way. The Advertising Proxy must publish `_matter._tcp` records on the LAN mDNS with an address the host can reach (mesh-local or OMR). Expect trouble because devices usually register an OMR address, which only exists when border routing is on.
- Symptoms that mean "go to option 2": the commissioning flow in HA fails at "finding the node on the network" or times out after the Thread join succeeded; `matter-server` logs cannot resolve or reach the node; `dns-sd`/`avahi-browse -r _matter._tcp` shows no usable AAAA; `ot-ctl netdata show` lists no OMR prefix (`ot-ctl br omrprefix` fails because BR is off).

**Option 2 (next):** border routing ON, no UDM change.
1. In `infra/k8s/otbr/deployment.yaml` remove `; ot-ctl br disable` from the postStart hook (keep `bbr disable` and `nat64 disable`). PR, merge, hard-refresh and sync `otbr`, restart the pod.
2. Check `ot-ctl br state` is `running`, `ot-ctl br omrprefix` and `onlinkprefix` show ULA prefixes, and `ot-ctl netdata show` lists the OMR prefix.
3. Expected side effects: RAs on `eno1` with an on-link ULA prefix and a route; LAN hosts gain ULA addresses (`ip -6 addr` on the workstation shows `fd..`). Check that AdGuard and general browsing still work (a ULA-only RA with no default route should not change IPv4 behaviour). Verify `sysctl net.ipv4.conf.all.rp_filter` is 0 and `dig @10.3.0.53 example.com` still answers.
4. Host forwarding is still not required for the Matter server on the same host. Do not set `net.ipv6.conf.all.forwarding=1` unless LAN clients other than tachyon must reach Thread devices; if so, set it per interface (`eno1`, `wpan0`) and set `accept_ra=2` on `eno1`, and re-verify Cilium (rp_filter, DNS).
5. Rollback: re-add `ot-ctl br disable` and restart, or scale `otbr` to 0. RA-learned addresses on LAN hosts expire within about 30 minutes.

**Option 3 (alternative to 2):** put a ULA on the LAN deliberately instead of letting OTBR invent one.
- ULA = Unique Local Address (RFC 4193, `fc00::/7`, in practice `fd00::/8`), the IPv6 counterpart of RFC 1918 private space; not routable on the internet.
- Generate a random /48: `printf 'fd%s\n' "$(openssl rand -hex 5)"` gives 40 random bits (`fdXX:XXXX:XXXX::/48`). Use `fdXX:XXXX:XXXX:1::/64` for the LAN. Record it in `docs/hld/segv-cluster.md`.
- UDM (UniFi Network, wording varies): Settings, Networks, LAN, IPv6: interface type Static, the /64, Router Advertisement on, DHCPv6 off (SLAAC). **Ask the user first:** it changes the whole LAN.
- Gotcha: with no WAN IPv6 the UDM RA may still claim to be a default router, so some clients try IPv6 first and fall back (slow connects). If seen, remove it.
- Then also do option 2 (border routing on); OTBR will use the LAN's existing prefix as its on-link prefix.

**Option 4 (last resort):** routable IPv6 for segv and the WAN (ISP prefix request, firewalling, cluster ingress, review of Cilium routing and host policies). Separate plan; the user wants all other avenues exhausted first. Cilium currently has IPv6 disabled (`enable-ipv6: false`), so it does not filter IPv6 host traffic.

### Testing once a Matter device exists (the user has none yet)
1. HA: Settings, Devices and services, add **Thread** (it discovers the border router; if not, add **Open Thread Border Router** with URL `http://otbr.home.svc:8081`) and set the network as preferred. Add **Matter** with URL `ws://matter-server.home.svc:5580/ws`.
2. Check `ot-ctl state` is `leader`, `ot-ctl dataset active` exists, and `matter-server` is running (`kubectl -n home logs deploy/matter-server`).
3. Commission with the HA companion app (phone needs Bluetooth, and the Thread credentials are shared from HA). Then use `ot-ctl child table` / `neighbor table` to see the device join.
4. Run `ot-ctl` as `kubectl -n home exec deploy/otbr -c otbr -- ot-ctl <cmd>`.
5. Back up the active dataset (`ot-ctl dataset active -x`) as a Secret in `scripts/secrets.list` before relying on the network (not done yet; Velero already backs the PVC).

### Canary sequence (steps 1 and 2 done 2026-11-06; verify rp_filter=0 and DNS after each)
1. Merge the new Deployment (replicas 0), sync, then scale to 1 with `hostNetwork` temporarily **false** in a throwaway copy: own pod netns, privileged only for the device. Check `ot-ctl state` forms a network over the real RCP at 921600/flow control. This cannot touch host networking.
2. Switch to `hostNetwork: true` with `--backbone-ifname eno1`. Watch `sysctl net.ipv4.conf.all.rp_filter`, `ip -6 addr/route`, DNS (`dig @10.3.0.53 example.com`) and pod health for 5 minutes. Roll back by scaling to 0 and, if needed, `sysctl --system` on the host.
3. Sync `matter-server`; add the Thread and Matter integrations in HA.

Fallback if the infra-link behaviour is unacceptable: separate plan for routable IPv6 (prefix request, firewalling, ingress, Cilium routing review).

## Design
- **Firmware:** OpenThread RCP (Thread only, decided). The SLZB-07 is dedicated to Thread; Zigbee is a separate dongle.
- **OTBR pod** (`ot-br-posix`, image pinned by digest): `hostNetwork: true` (it manages `wpan0`, ip6tables/ipset, and mDNS on `eno1`), `NET_ADMIN`/`NET_RAW`, `/dev/net/tun`, and the serial device via `hostPath` of the by-id path. Pinned to tachyon (`nodeSelector`; the cluster is a single node today). Needs a `container_file_t`-compatible way to open the tty: use `securityContext.seLinuxOptions.type: spc_t` (privileged is the fallback). Exposes its REST API on `:8081` through a ClusterIP Service `otbr` in ns `home`.
- **Matter server pod** (`python-matter-server`, pinned): `hostNetwork: true` (needs LAN IPv6/mDNS), websocket `:5580`, state on a ZFS-backed PV. Service `matter-server`.
- **Home Assistant:** unchanged pod. Add the Thread integration (OTBR URL `http://otbr.home.svc:8081`) and the Matter integration (`ws://matter-server.home.svc:5580/ws`) by hand in the UI.
- Alternative considered: a `squat/generic-device-plugin` DaemonSet to hand out `/dev/ttyUSB*` as a resource. It avoids `spc_t`/hostPath but adds a component for one device. Revisit only if a second serial device appears.

## Steps

### 1. Flash (on this workstation, device already plugged in)
1. Read-only check: `lsusb`, `ls -l /dev/serial/by-id/`, current firmware via SMLIGHT's flasher page or `universal-silabs-flasher --device <by-id> probe`.
2. Firmware (done 2026-11-05): `smlight_slzb07_openthread_rcp_2.7.2.0_GitHub-fb0446f53_921600_hw_flow.gbl` from the community release `Nerivec/silabs-firmware-builder` `v2025.6.2-update1` (listed in SMLIGHT's device-update manual; plain `slzb07` = MG21). sha256 `556eafbecb631268abee99c59df7ca6dc4ebe9064c647978d66ee314a52e59b0`. The newer `v2026.6.2-pre1` build has metadata v3, which `universal-silabs-flasher` 1.3.0 cannot parse. SMLIGHT's web flasher did not work (stock EZSP firmware; it wants a router build).
3. Flash (done 2026-11-05): `universal-silabs-flasher --device /dev/ttyUSB0 --bootloader-reset rts_dtr flash --firmware <gbl>` (the `slzb07` reset method needs a GPIO chip and fails here). The port needs the user in `uucp` (or an ACL, lost on each reset).
4. Verified: a Spinel NCP_VERSION query returns `SL-OPENTHREAD/2.7.2.0_GitHub-fb0446f53; EFR32` with 921600 baud and RTS/CTS flow control. The stock `probe` cannot detect it (no flow control). **OTBR radio URL:** `spinel+hdlc+uart:///dev/serial/by-id/<id>?uart-baudrate=921600&uart-flow-control`.

### 2. Move the dongle to tachyon
1. Unplug here, plug into tachyon. Prefer a short USB 2.0 extension cable away from the blade's chassis/USB3 ports (USB3 noise degrades 2.4 GHz).
2. `timeout 20 ssh -o BatchMode=yes -o ConnectTimeout=10 core@tachyon.lan 'ls -l /dev/serial/by-id/'`; the same by-id name must appear.

### 3. Manifests (this worktree, `slzb07-thread`) - drafted 2026-11-05
Done, validated with `kubectl kustomize`, `kubectl apply --dry-run=server` against segv (read-only), `helm lint` and `scripts/test/storage-bindings.sh` (16 PVs match 16 PVCs):
1. `infra/k8s/otbr/` and `infra/k8s/matter-server/` (kustomize, ns `home`): PVC, Recreate Deployment pinned to tachyon with `hostNetwork`, Service. OTBR is `privileged` with the by-id device mounted at the same path; its radio URL is `...?uart-baudrate=921600&uart-flow-control` and backbone interface `eno1`. Images are pinned by digest (`openthread/otbr` publishes only `latest`; `python-matter-server` 8.1.0).
2. Catalog templates `infra/k8s/catalog/templates/{otbr,matter-server}.yaml` (no auto-sync).
3. PVs `pv-otbr.yaml` and `pv-matter-server.yaml` (1Gi each, datasets `data/k8s/otbr` and `data/k8s/matter-server`), listed in the storage kustomization; `storage-bindings.sh` renders both apps' claims.
4. No NetworkPolicy: ingress policies do not apply to `hostNetwork` pods. The existing `host-allow-cluster` already admits pod-to-node traffic (HA reaches `otbr:8081` and `matter-server:5580`), and `host-allow-lan` does not open them to the LAN. Cilium has IPv6 disabled, so IPv6 host traffic (Thread, Matter, mDNS6) is not filtered by it. Add a host policy only if Hubble shows IPv4 drops, in audit mode first.
5. Velero already covers ns `home`; both pods carry `backup.velero.io/backup-volumes: data`.

Still to do before deploy (needs the user's go): create the two ZFS datasets on tachyon.

### 4. Deploy (needs the user's go; segv is the real cluster)
1. Open a PR, merge to `main`, fast-forward `main`.
2. Hard-refresh `root`, sync `catalog` apps, then sync `otbr` and `matter-server` by patching `operation`.
3. Check: OTBR logs show the RCP up and `wpan0` created; `ot-ctl state` is `disabled` -> form a network (`ot-ctl dataset init new`, `commit active`, `ifconfig up`, `thread start`) -> `leader`.
4. In HA: add Thread (OTBR URL) and set it as the preferred network, then add Matter (server URL). Commission a test device with the HA companion app.

### 5. Backup and recovery
- Export the active Thread dataset (`ot-ctl dataset active -x`) as a Secret listed in `scripts/secrets.list` and exported with `scripts/export-secrets`, so a rebuild restores the same network and paired devices do not need re-pairing.
- Confirm a Velero backup covers `otbr` and `matter-server` volumes.

## Risks and open questions
- **IPv6 on the LAN.** Not configured (see "IPv6 strategy"). If Thread fails for that reason, the fix is the separate routable-IPv6 plan.
- **Cilium + hostNetwork.** Host policies apply to the pod; mDNS multicast may need explicit rules. Verify with Hubble in audit mode.
- **Reboots.** After a node reboot the pod takes about 10 minutes to return (see CLAUDE.md). The dongle is re-enumerated; the by-id path is unchanged.
- **Single point of failure.** One RCP, one node. Thread devices rejoin when the dataset is restored (step 5).
- **Firmware source trust.** Flash only a vendor-signed/checksummed build.
- `ot-br-posix` has no stable tagged release: pin an image by digest and record the reason.

## Decisions (2026-11-05)
1. Thread-only firmware. Zigbee runs on a separate dongle.
2. OTBR and the Matter server share one namespace: `home` (no new namespace, baseline policy or Velero entry).
3. Try Thread without IPv6 first. The ISP supports IPv6, but no prefix request or IPv6 firewalling exists; routable IPv6 is a separate plan, only if this fails. Nothing here may open GUA.

## IPv6 strategy
Order of attack, decided 2026-11-05:
1. Deploy Thread with **no IPv6 changes** (no UDM ULA, no prefix request). OTBR's own RAs and link-local mDNS are all it gets. The OTBR container sets `net.ipv6.conf.all.forwarding=1` and `net.ipv6.conf.eno1.accept_ra=2` at start (no butane change); verify they persist.
2. If commissioning or control fails for want of IPv6, **stop and write a separate plan for fully routable IPv6** (prefix request from the ISP, firewalling, cluster ingress, and a review of the Cilium routing and host policies), and get that working safely before retrying Thread. A UDM ULA is not an intermediate step.
Not in scope here: any change to the UDM, ISP or firewall.

