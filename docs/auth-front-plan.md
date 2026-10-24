# Authentication for internet-facing apps

Follows `docs/keycloak-plan.md`. Supersedes the earlier Envoy Gateway plan (kept below as the deferred alternative).

Conventions: `STOP and ask` = the user says go in the conversation first. Secrets never enter the repo, logs or chat.

## Policy (decided 2026-10-24)
1. An app with native OIDC uses it against Keycloak (realm `segv`) and is **not** fronted.
2. An app whose clients speak a proprietary protocol cannot sit behind a login redirect. Vaultwarden is the case: only its
   `/admin` path is fronted, and only if the admin page is enabled.
3. Immich will be internet-facing and uses its own SSO.
4. Nothing else needs a front today.

## Approach: oauth2-proxy, not Envoy Gateway
The scope is one path on one app. oauth2-proxy covers it with one Deployment and avoids everything Envoy Gateway drags in:
the Gateway API CRD mismatch (v1.3.0 for Cilium 1.18.14 against v1.6.1 for the only Envoy Gateway release that supports
Kubernetes 1.36), a second load-balancer address, new Cilium policies for another proxy, and retiring the Cilium Gateway.

The Cilium Gateway has no auth-request hook, so the proxy sits in the request path: an `HTTPRoute` rule sends the protected
path (and `/oauth2/*`) to oauth2-proxy, which authenticates against Keycloak and proxies to the app. No CRDs, no change to
the Gateway, and the existing wildcard certificate and source allow-list apply unchanged.

What this gives up: one central policy resource, JWT validation for API clients at the edge, claim-based rules in YAML, and a
single data-plane proxy for every route. Costs: one proxy instance per fronted app, and an extra hop on fronted paths.
**Revisit Envoy Gateway** if more than a few web-only apps need fronting, or an API needs bearer-token validation at the
edge (see the appendix).

## Findings
- Vaultwarden's admin page is **disabled today**: `ADMIN_TOKEN` is not set, and `https://vault.segfault.me/admin` answers
  "The admin panel is disabled". There is nothing to front until it is enabled. Alternative to a front: leave it off, or
  route `/admin` only on `lab.segfault.me` (LAN).
- Only `segfault.me/auth` and `vault.segfault.me` are internet-facing now. `lab`, `home` and `photos` are LAN-only.
- Keycloak's namespace baseline policy admits only same-namespace and Gateway traffic, so oauth2-proxy needs its own
  `CiliumNetworkPolicy` to reach `keycloak-service:8080`.
- The realm user `alxbl` has no email. oauth2-proxy wants one; set `--oidc-email-claim=preferred_username` and
  `--email-domain=*` (the realm admits only the linked GitHub account) rather than putting an email in the realm.
- `KeycloakOIDCClient` has no protocol-mapper field, which is fine: oauth2-proxy verifies the ID token, whose `aud` is the
  client id. A mapper is only needed to accept bearer access tokens.
- Cilium Gateway ALPN (`gatewayAPI.enableAlpn`): the earlier recommendation not to enable it rested on retiring that
  Gateway, which no longer holds. It is still not worth it: global to every listener, also enables `appProtocol` selection,
  and the only gain is h2 on the cortex hop. Revisit only for a concrete need.

## Phases
### A. Immich with native SSO (when Immich is deployed)
- `KeycloakOIDCClient` `immich` (confidential; redirect URIs `https://photos.segfault.me/auth/login`,
  `https://photos.segfault.me/user-settings`, `app.immich:///oauth-callback`). Client secret in a Secret listed in
  `scripts/secrets.list`.
- Immich OAuth settings (issuer `https://segfault.me/auth/realms/segv`, client id and secret) live in its configuration.
  The secret must not be in a ConfigMap: move the configuration to a Secret (`configurationKind: Secret` in the chart).
  Disable password login and auto-registration once SSO works; the realm only admits `alxbl`.
- Public exposure, two options to choose between (STOP and ask):
  - Same as Vaultwarden: Cloudflare proxies `photos.segfault.me` straight to the home address (the Gateway already admits
    Cloudflare ranges). No cortex change.
  - Through cortex: a `photos.segfault.me` server block in nginx proxying everything to nghttpx, with
    `client_max_body_size 0`, `proxy_request_buffering off` and long timeouts for uploads.
  Either way the Cloudflare proxy caps request bodies (100 MB on the free plan), which breaks large video uploads from the
  app. Options: DNS-only record for this name (exposes the origin address), a paid plan, or accept it.
- Add the hostname to the Cloudflare DNS and verify the Immich mobile app's OAuth flow end to end.

### B. Vaultwarden `/admin` (only when `ADMIN_TOKEN` is set)
- `KeycloakOIDCClient` `vaultwarden-admin` (confidential), redirect `https://vault.segfault.me/oauth2/callback`.
- oauth2-proxy (Helm chart from `https://oauth2-proxy.github.io/manifests`, repository entry in
  `infra/system/argocd/overlays/helm-repositories.yaml`, pin the chart version when implementing) in the `home` namespace:
  `--provider=keycloak-oidc`, `--code-challenge-method=S256`, `--upstream=http://vaultwarden:80`, `--reverse-proxy` with
  `--trusted-proxy-ip` set, and a role restriction (`--allowed-role`). Reach Keycloak in-cluster: `--skip-oidc-discovery`
  with `--login-url` (public), `--redeem-url` and `--oidc-jwks-url` (`http://keycloak-service.keycloak:8080/auth/...`) and
  `--oidc-issuer-url` the public issuer, so nothing hairpins through Cloudflare. Check `--insecure-oidc-skip-issuer-verification`
  is not needed (the token `iss` is the public URL either way).
- Secrets (client secret, cookie secret) created by an extension of `scripts/keycloak-secrets`, listed in `secrets.list`.
- `HTTPRoute` `vault.segfault.me`: `/admin` and `/oauth2` to oauth2-proxy, everything else to Vaultwarden unchanged. The
  Bitwarden clients never touch `/admin`.
- `CiliumNetworkPolicy` in `keycloak` allowing oauth2-proxy to `keycloak-service:8080`.
- Verify: unauthenticated `/admin` redirects to Keycloak; after login the Vaultwarden token prompt shows; `/api`,
  `/identity` and the web vault are untouched; a Bitwarden client still syncs.

### C. Later
Add an instance per newly fronted app. Re-open the Envoy Gateway question if that list grows.

## Risks
- The fronted path depends on Keycloak: if it is down, `/admin` is unreachable (it fails closed). Acceptable for an admin page.
- oauth2-proxy cookies are per host; do not share a cookie domain across hosts without a reason.
- Do not front Keycloak, Argo CD's own login or anything the proxy itself needs.

## Appendix: Envoy Gateway findings (deferred alternative)
- Compatibility: Envoy Gateway v1.9 (Envoy 1.39.x, Gateway API **v1.6.1**, Kubernetes 1.33 to 1.36) is the only release
  covering Kubernetes 1.36 (segv is v1.36.2). v1.8 expects Gateway API v1.5.1 and tops out at Kubernetes 1.35. segv has
  Gateway API **v1.3.0 standard**, installed from `infra/system/cilium/gateway-api` because Cilium 1.18.14 (pinned) targets it.
- The chart can ship its own Gateway API CRDs or skip them (`crds.enabled=false`, or the separate `gateway-crds-helm` chart)
  and renders safe-upgrade admission policies. Two controllers would share one CRD set: rehearse on dev before segv.
- It needs its own load-balancer address (the `lan` pool has only `10.3.0.2/32`, shared with smbd), its own ingress policy
  (`gateway-allow-sources` selects `reserved:ingress`, i.e. Cilium's proxy), and `externalTrafficPolicy: Local` to keep client
  addresses.
- Features: `SecurityPolicy` `oidc` (PKCE, encrypted cookies, refresh on by default, `denyRedirect`, `passThroughAuthHeader`),
  `jwt` (remote JWKS, issuer and audience checks, 401 on missing token), `authorization` rules on JWT claims. Redirect and
  logout paths must sit under the target route. Whether `jwt` and `oidc` combine cleanly in one policy is undocumented.
- ALPN: Envoy Gateway advertises `h2` then `http/1.1` on HTTPS listeners by default (`ClientTrafficPolicy` `tls.alpnProtocols`
  overrides it); the cortex hop could then use `;proto=h2` in `nghttpx.conf`.
