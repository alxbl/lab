# Keycloak on segv, then Envoy Gateway

Keycloak is deployed and the GitHub login works (verified 2026-10-24). Envoy Gateway, the enforcement point for "no valid
token, no access", is the remaining phase and starts from here.

## Result
- `https://segfault.me/auth` flows Cloudflare, cortex nginx, nghttpx, the segv Cilium Gateway, Keycloak 26.8.1.
- Keycloak is deployed by the Keycloak Operator (OLM, v26.8.1, pinned, manual InstallPlan approval) with Postgres from CNPG
  on the dataset `data/k8s/keycloak-db` (10G).
- Realm `segv`: GitHub identity provider, registration off, user `alxbl` pre-linked to GitHub id 860411. Every other GitHub
  account is rejected by the `first broker login deny` flow.
- Pilot client `test-app` (public, https://www.keycloak.org/app/), defined as a `KeycloakOIDCClient` CR.
- The admin console and the `master` realm are served only on `lab.segfault.me` (LAN). The public host exposes
  `/auth/realms/segv`, `/auth/resources` and `/auth/js`; the restriction is in the HTTPRoute, not only at cortex.

## Where things live
- `infra/system/keycloak` (Argo app `keycloak`, no auto-sync): namespace, Subscription, CNPG `Cluster`, `Keycloak` CR,
  routes, `KeycloakRealmImport` `segv`, `KeycloakOIDCClient` `test-app`.
- `infra/system/storage/base/pv-keycloak-db.yaml`, the claim in `scripts/test/storage-bindings.sh`, the `keycloak` baseline
  policy in `infra/system/cilium/policies/overlays/segv/namespaces.yaml`.
- Secrets (Proton Drive, listed in `scripts/secrets.list`, created by `scripts/keycloak-secrets`):
  `keycloak-bootstrap-admin`, `keycloak-admin` (operator service account), `keycloak-github` (OAuth app; prompted with `--github`).
- Edge, in `alxbl/segfault.me` (PR #1): `build/nginx/conf.d/segfault.me.conf` (`/auth/`), `build/nghttpx/etc/nghttpx.conf`,
  `build/docker-compose.yaml`. The GitHub OAuth callback is `https://segfault.me/auth/realms/segv/broker/github/endpoint`.

## Decisions
1. **Apex certificate.** The Gateway certificate already lists `segfault.me` and `*.segfault.me`; nothing to change.
2. **Path.** `http-relative-path=/auth`, hostname `https://segfault.me/auth`, admin hostname `https://lab.segfault.me/auth`.
3. **Realm IaC.** `KeycloakRealmImport` creates a realm once and never reconciles it; changing the realm means a new import.
   Clients are `KeycloakOIDCClient` CRs, which do reconcile. Terraform or `keycloak-config-cli` stays an option if drift hurts.
4. **GitHub user restriction.** Supplying `authenticationFlows` replaces Keycloak's built-in flows, so the import lists the
   whole default set (exported from a throwaway 26.8.1 realm) plus `first broker login deny`. Regenerate that block when
   upgrading Keycloak.
5. **Secrets.** Created out of band; realm secrets reach the import through `placeholders`.
6. **Backend hop is HTTP/1.1, not h2.** The Gateway negotiates no ALPN (Cilium `gatewayAPI.enableAlpn` is off, a cluster-wide
   setting) and Keycloak does not need h2. nghttpx stays in the chain; adding `;proto=h2` to its backend is the switch once
   ALPN is enabled.
7. **Verified backend TLS.** The old nghttpx config used `insecure=yes`. The image has no CA bundle, so the host's is mounted,
   and the backend is the alias `origin.segfault.me` (`extra_hosts`, address from git-ignored `build/.env`), which matches the
   Gateway's wildcard certificate.
8. **No key in nghttpx.** The nginx to nghttpx hop is plain HTTP on a private docker network.

## Traps found
- The operator's client controller needs `features.enabled: client-admin-api:v2` on the `Keycloak` CR.
- It also needs the `keycloak-admin` Secret (a master-realm service account). Keycloak creates that account only when it
  initialises `master`, so on the first deployment it was created once through the admin API. A rebuild gets it on first start.
- The operator does not URL-encode the client secret: keep it hex (base64 gives `invalid_client_credentials`).
- The operator Deployment is owned by OLM: `rollout restart` is reverted; delete the pod instead.
- `cilium-policies` fails to sync if the `keycloak` namespace does not exist yet; sync `keycloak` first.
- A rebuild must approve the InstallPlan by hand and apply `keycloak-secrets` before the `Keycloak` CR starts.

## Live state on cortex (not covered by `setup.sh`)
The host does not run the compose stack in the repo. The blog is the `segv-tls` nginx container (configs under `/app/nginx`,
behind sslh on 443). Added by hand: container `nghttpx` (`--restart unless-stopped`, config in `/app/nghttpx`), docker network
`edge` with `segv-tls` attached, and the `/auth/` block in `/app/nginx/conf.d/segfault.me.conf` (backup `.bak-pre-keycloak`).
Recreating `segv-tls` with `docker run` drops the `edge` attachment (`docker network connect edge segv-tls`). The cluster's
public address is baked into the `nghttpx` container at start (`--add-host origin.segfault.me:<ip>`): if the WAN address
changes, recreate the container, or put a DNS-only record in front of it.

## Follow-ups
- **Envoy Gateway (phase 6, own plan).** Install beside the Cilium Gateway on a second IP, `SecurityPolicy` with `oidc` for
  browsers and `jwt` for bearer clients against the `segv` realm, exempt Keycloak and health endpoints, migrate routes one by
  one. Check how OIDC and JWT behave on one target before relying on bearer pass-through. Per-app Keycloak clients are
  `KeycloakOIDCClient` CRs.
- Decide on `gatewayAPI.enableAlpn` (decision 6).
- The Gateway admits Cloudflare ranges on 443 and routes on the Host header, so a Cloudflare-proxied name of someone else's
  zone pointing at the WAN address with `Host: lab.segfault.me` would reach the LAN-only routes, Keycloak admin included.
  Worth closing when the Envoy Gateway work reshapes the routes.
- The stale local branch `keycloak` (hand-rolled chart, `88c00c1`) is superseded; delete it when convenient.
- Test the deny flow with a second GitHub account (not yet done).
