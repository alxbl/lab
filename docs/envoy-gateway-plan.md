# Envoy Gateway in front of segv

Follows `docs/keycloak-plan.md`. Goal: requests without a valid Keycloak credential never reach an internet-facing app;
browsers are sent through the login flow, API clients get a 401.

Conventions: `STOP and ask` = the user says go in the conversation first. Secrets never enter the repo, logs or chat.
Rehearse on the dev cluster (`infra/clusters/dev`, safe to rebuild) before anything touches segv.

## What is actually internet-facing
| Name | Reaches | Path today | Client types |
|---|---|---|---|
| `segfault.me/auth` | Keycloak | Cloudflare, cortex, Gateway | browsers, OIDC apps |
| `vault.segfault.me` | Vaultwarden | Cloudflare, Gateway | Bitwarden apps and extensions, browsers |
| `lab.segfault.me` | Argo CD `/argocd`, Jellyfin `/watch`, Grafana `/grafana`, Keycloak admin `/auth` | LAN only | browsers |
| `home.segfault.me` | Home Assistant | LAN only | browsers, companion apps |
| `photos.segfault.me` | Immich (not ready) | LAN only | browsers, phone app |

Two consequences:
- Only Keycloak and Vaultwarden are reachable from the internet. Vaultwarden's own clients speak a proprietary token
  protocol and cannot follow an OIDC redirect or present a Keycloak token, so putting it behind the front would lock out the
  apps. Browsers can use the web vault through it.
- "Front everything" therefore splits by client type (below), and needs a decision per app.

## Decisions needed from the user
1. **Vaultwarden.** Options: (a) leave as is (its own auth, rate limiting, optional 2FA); (b) front only the web vault and
   admin paths (`/`, `/admin`) and exempt `/api`, `/identity`, `/notifications`, `/icons` that the apps use; (c) restrict
   by source. Recommendation: (b) for `/admin` only, otherwise (a).
2. **Which apps get the front.** Candidates are web-only UIs without strong native auth. Argo CD, Grafana, Jellyfin and
   Immich support OIDC themselves; prefer native OIDC against Keycloak (a client CR each) over proxy login for those.
3. **New internet-facing apps planned?** Anything exposed later inherits the pattern in this plan.

## Findings that constrain the design
- Gateway API CRDs are **v1.3.0 standard**, installed from `infra/system/cilium/gateway-api` because Cilium 1.18.14 (pinned,
  do not bump) targets v1.3.0. Envoy Gateway v1.9 (the only current release supporting Kubernetes 1.36; segv is v1.36.2)
  expects Gateway API **v1.6.1**; v1.8 expects v1.5.1 and tops out at Kubernetes 1.35. Two controllers, one CRD set.
- The Envoy Gateway chart can ship its own Gateway API CRDs or skip them (`crds.enabled=false`, or the separate
  `gateway-crds-helm` chart); it also renders safe-upgrade ValidatingAdmissionPolicies that guard the CRD version. Do not let
  two sources manage the same CRDs.
- The LB pool `lan` has a single address, `10.3.0.2/32`, shared by the Gateway (80/443) and smbd (445). Envoy Gateway needs
  its own address.
- `gateway-allow-sources` (`CiliumClusterwideNetworkPolicy`) selects `reserved:ingress`, i.e. Cilium's Gateway proxy only.
  Envoy Gateway's proxy pods are ordinary pods in `envoy-gateway-system` and need their own ingress policy, the same
  Cloudflare/LAN/cortex source list, and the namespace baseline pattern from `policies/overlays/segv/namespaces.yaml`.
- Source addresses: Cilium's Gateway uses `externalTrafficPolicy: Cluster` (`gatewayAPI.externalTrafficPolicy`). Envoy
  Gateway's Service should use `Local`, or the CIDR allow-list and logs see the node address instead of the client.

## Design
- Envoy Gateway runs beside the Cilium Gateway on a second address; routes move over one by one. The Cilium Gateway is
  retired at the end (`gatewayAPI.enabled=false`), which also ends the two-controller period.
- **Browsers:** `SecurityPolicy` `oidc` (authorization code with PKCE; tokens kept in encrypted cookies; refresh on by
  default) against realm `segv`. `redirectURL` and `logoutPath` must sit under the target HTTPRoute's host and path.
- **API clients:** `jwt` (remote JWKS from Keycloak, issuer and audience checked). A missing or invalid token is a 401.
  `denyRedirect` on header matchers (for example `Accept: application/json`) keeps machine clients from being redirected.
- **Combining both:** `passThroughAuthHeader` skips the OIDC step when a bearer header the JWT filter extracts is present.
  Nothing in the API types forbids setting `jwt` and `oidc` together, but the exact ordering and the status of a
  bearer-less browser request when `jwt.optional` is false are not documented: **verify in the rehearsal** before relying
  on it.
- **Authorization:** `SecurityPolicy.authorization` rules on JWT claims. The `segv` realm has one user, but a rule on a
  Keycloak role or group (rather than "any valid token") keeps a future second user from getting everything. Needs a role
  mapper on the client.
- **Policy scope:** attach to routes, not the Gateway, so Keycloak itself, ACME challenges and health endpoints stay
  outside it by construction.
- **In-cluster reachability:** the proxy must fetch discovery and JWKS from Keycloak. `segfault.me` resolves to Cloudflare,
  so a hairpin through the internet is wasteful and fragile. Tokens carry `iss=https://segfault.me/auth/realms/segv`
  regardless of the URL used, so point the fetch at `keycloak-service:8080` through a `Backend` and keep the public issuer.
  Check how the OIDC provider's `backendCluster` and the JWT `remoteJWKS.backendRefs` behave (the OIDC provider type notes
  `backendRef` is unsupported).
- **Per-app clients:** one `KeycloakOIDCClient` CR per protected app (confidential, client secret in a Secret listed in
  `scripts/secrets.list`).
- **ALPN / HTTP/2:** Envoy Gateway advertises `h2` then `http/1.1` on HTTPS listeners by default, and `ClientTrafficPolicy`
  `tls.alpnProtocols` overrides it. Nothing to enable. Once the cortex hop goes through Envoy Gateway, add `;proto=h2` to
  `build/nghttpx/etc/nghttpx.conf` in `alxbl/segfault.me`. **Do not** enable `gatewayAPI.enableAlpn` on Cilium: it is global
  to every Cilium Gateway listener and also switches on `appProtocol` backend selection, for a gateway that is being retired.

## Phases
### 0. Rehearsal on dev (no approval needed)
- Reproduce the two-controller state: Cilium 1.18.14 with Gateway API CRDs at the target version, then Envoy Gateway.
  Answer: does Cilium's gateway controller stay healthy on v1.6.1 CRDs? If not, the options are (a) a window with no
  Cilium Gateway, switching straight to Envoy Gateway, or (b) staying on the CRD version Cilium wants and using an Envoy
  Gateway release for it (out of support, outside the Kubernetes 1.36 test range: avoid).
- Keycloak is not on dev; use a throwaway Keycloak (operator or a plain container) with realm `segv` imported.
- Prove: OIDC redirect and cookie session; bearer JWT pass-through; invalid bearer 401; `denyRedirect`; claim-based
  `authorization`; JWKS fetch through a `Backend`; policy attached per route leaves the others open.
- Write the findings back into this file; they replace the "verify" items above.

### 1. Prepare segv (STOP and ask before each apply that touches the live Gateway or the Cilium chart)
- Add `10.3.0.3/32` (or another free address) to the `lan` pool; decide the Gateway API CRD version from phase 0.
- Argo apps (catalog templates, no auto-sync): `envoy-gateway` (Helm chart, `ServerSideApply=true`, repository entry in
  `infra/system/argocd/overlays/helm-repositories.yaml`) and its resources (`GatewayClass`, `EnvoyProxy` with the Service
  annotation for the address and `externalTrafficPolicy: Local`, `Gateway` with the wildcard certificate).
- `envoy-gateway-system` namespace baseline policy plus the Cloudflare/LAN/cortex source allow-list for the proxy pods.
- Router and cortex: the new address is internal only until a route moves; no external change yet.

### 2. First route
- Pick a low-stakes LAN route (Grafana at `lab.segfault.me/grafana`) behind the new Gateway on its own test hostname, attach
  `SecurityPolicy` with a `KeycloakOIDCClient`, test as the user (browser flow, logout), then with a bearer token.
- Keep the Cilium route until the new one is accepted.

### 3. Migrate
- Move routes one at a time; point `lab.segfault.me`'s internal DNS at the new address when the last LAN route is over.
- Internet-facing: move `segfault.me/auth` and `vault.segfault.me` last. Cloudflare and the router's port forward target the
  address that currently serves them: change it deliberately (STOP and ask) and keep the old Gateway reachable for rollback.
- cortex: no change except `;proto=h2` once the origin negotiates ALPN.

### 4. Retire the Cilium Gateway
- STOP and ask. `gatewayAPI.enabled=false` in `infra/system/cilium/values.yaml` (chart stays pinned at 1.18.14), remove
  `gateway-allow-sources`, the Cilium `GatewayClass`, and the CRD workarounds that only existed for it.

## Risks and rollback
- A policy or CRD mistake on the live Gateway breaks every route: prove it on dev first; each route move is reversible by
  restoring the old `HTTPRoute`.
- OIDC cookies are per host unless `cookieDomain` is set; setting it late needs browser cookies cleared.
- Keycloak is a single instance: while it is down, OIDC routes fail closed (that is the point), and JWT routes keep working
  for tokens already issued as long as the cached JWKS is valid.
- Do not put Keycloak, Argo CD's own login or the Envoy Gateway control plane behind a policy that depends on them.

## Deliverables
- Rehearsal notes in this file, then PRs per phase; Argo apps and policies in the lab repo; a `KeycloakOIDCClient` per
  protected app; `scripts/secrets.list` entries and an `export-secrets` run for each new client secret.
