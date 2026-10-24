# Authentication for internet-facing apps

Follows `docs/keycloak-plan.md`. Records the access decisions and what is left; the Envoy Gateway findings are kept as the deferred alternative.

Conventions: `STOP and ask` = the user says go in the conversation first. Secrets never enter the repo, logs or chat.

## Decisions (2026-10-24)
1. An app with native OIDC uses it against Keycloak (realm `segv`) and is not fronted.
2. **No proxy front for now.** Vaultwarden's clients speak a proprietary protocol and cannot sit behind a login redirect, and
   its admin page stays disabled (`ADMIN_TOKEN` unset, answers "The admin panel is disabled"). Nothing else is fronted.
3. **ALPN stays off** on the Cilium Gateway (`gatewayAPI.enableAlpn`): it is global to every listener, also enables
   `appProtocol` selection, and the only gain is h2 on the cortex hop. Revisit only for a concrete need.
4. **Routing of names.** Only the apex `segfault.me` goes through cortex (the blog stays off the home link, so it stays up
   when the home link does not; `/auth` rides the same path). Every other public name, `vault.segfault.me` today and
   `photos.segfault.me` for Immich, goes Cloudflare straight to segv.
5. Envoy Gateway and oauth2-proxy are both deferred; see the appendices for when to reopen them.

## What this leaves to do: Immich with native SSO (when Immich is deployed)
- `KeycloakOIDCClient` `immich` (confidential; redirect URIs `https://photos.segfault.me/auth/login`,
  `https://photos.segfault.me/user-settings`, `app.immich:///oauth-callback`). Client secret in a Secret listed in
  `scripts/secrets.list`, created by an extension of `scripts/keycloak-secrets`.
- Immich OAuth settings (issuer `https://segfault.me/auth/realms/segv`, client id and secret) are part of its configuration.
  The secret must not be in a ConfigMap: move the configuration to a Secret (`configurationKind: Secret` in the chart).
  Turn off password login and auto-registration once SSO works; the realm only admits `alxbl`.
- Exposure needs no cortex change: the `photos.segfault.me` HTTPRoute already exists, the Gateway already admits Cloudflare's
  ranges, and the wildcard certificate covers the name. What is missing is the Cloudflare DNS record (proxied) for
  `photos.segfault.me`, and checking that the router forwards 443 as it does for `vault.segfault.me`.
- **Open:** the Cloudflare proxy caps request bodies (100 MB on the free plan), which breaks large video uploads from the
  phone app. Options: a DNS-only record for this name (exposes the home address), a paid plan, or accept it.
- Dependency to know about: sign-in to Immich needs Keycloak, which is served through cortex and then the home link; if
  either is down, SSO login fails (an existing session keeps working).
- Verify the mobile app's OAuth flow end to end, and that a second GitHub account is rejected.

## Risks
- Anything exposed later inherits the same questions: native OIDC if the app has it, otherwise decide explicitly.
- Do not front Keycloak, Argo CD's own login or anything a proxy itself would need.

## Appendix: if a front is needed later, oauth2-proxy
Fits a handful of web-only apps with no CRD or Gateway changes: the Cilium Gateway has no auth-request hook, so the proxy
sits in the path (an `HTTPRoute` rule sends the protected path and `/oauth2/*` to it, and it proxies to the app).
- Chart `https://oauth2-proxy.github.io/manifests` (repository entry in `infra/system/argocd/overlays/helm-repositories.yaml`).
- `--provider=keycloak-oidc`, `--code-challenge-method=S256`, `--upstream=<app>`, `--reverse-proxy` with `--trusted-proxy-ip`,
  `--allowed-role`. The realm user has no email: use `--oidc-email-claim=preferred_username` and `--email-domain=*`.
- Reach Keycloak in-cluster to avoid a hairpin through Cloudflare: `--skip-oidc-discovery` with the public `--login-url`,
  and `--redeem-url` and `--oidc-jwks-url` on `http://keycloak-service.keycloak:8080/auth/...`, public `--oidc-issuer-url`.
  The `keycloak` namespace baseline policy needs an allowance for the proxy.
- One `KeycloakOIDCClient` and one proxy instance per fronted app. Costs: an extra hop, and no central policy or edge JWT
  validation. Reopen Envoy Gateway if the list grows beyond a few apps or an API needs bearer-token validation.

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
