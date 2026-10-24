# Keycloak on segv, then Envoy Gateway

Keycloak goes first and stands alone. Envoy Gateway (the enforcement point for "no valid token, no access") is a separate
phase that starts only after Keycloak has passed the checks in phase 5.

Conventions: `STOP and ask` = the user says go in the conversation first. Secrets never enter the repo, logs or chat.

## Goal
- Keycloak reachable at `https://segfault.me/auth`, via Cloudflare, `cortex.segfault.me` (nghttpx) and segv's Cilium Gateway.
- Deployed by the Keycloak Operator (OLM) with Postgres from CNPG on a dedicated ZFS dataset.
- Realm configuration is code. GitHub is the identity provider and only `alxbl` may log in.
- Later (phase 6): Envoy Gateway enforces OIDC/JWT in front of internet-facing apps, using this Keycloak.

## State found in the repo (2026-10-24)
- `infra/system/keycloak` holds only an OLM `Subscription` (`keycloak-operator`, channel `fast`, `installPlanApproval: Manual`).
  The Argo `keycloak` app exists in `infra/system/catalog` and is deliberately unsynced.
- `infra/system/postgres` installs the CNPG operator (chart 0.29.0). The Argo `cnpg` app is also unsynced.
- `infra/system/olm` installs OLM v0.46.0. Whether it is synced and healthy on segv is unverified.
- Gateway: `https-in-gw` (class `cilium`, ns `gateway`), HTTPS listener with wildcard `*.segfault.me`, LB `10.3.0.2`.
  Routes live in `infra/k8s/gateway/overlays/segv/routes.yaml`.
- Postgres precedent: `infra/k8s/immich/resources/pg-immich.yaml` (CNPG `Cluster`, static `local-zfs` PV via `pvcTemplate`,
  PV in `infra/system/storage/base/pv-immich-db.yaml`, claim special-cased in `scripts/test/storage-bindings.sh`).
- A local branch `keycloak` (`88c00c1 keycloak wip`) holds a hand-rolled Helm chart in `charts/keycloak`. It does not use the
  operator, so this plan supersedes it. Do not delete the branch without asking.
- The `prompts/06-keycloak.md` brief (outside the repo) is the source of the requirements above.

## Decisions to make (document the choice in the PR)
1. **Wildcard vs apex.** `*.segfault.me` does not cover `segfault.me` itself. Check `infra/k8s/gateway/base/certificate.yaml`
   `dnsNames`. If the apex is missing, either add it to the certificate or terminate TLS for the apex only at Cloudflare/cortex and
   speak HTTPS to the Gateway under a covered name.
2. **Path vs host.** `/auth` means `KC_HTTP_RELATIVE_PATH=/auth` and a hostname that includes the path. Confirm Cloudflare and
   cortex forward `/auth` unchanged (no prefix stripping) and set the proxy headers the operator expects.
3. **Realm IaC.** The operator's `KeycloakRealmImport` CR is create-only (it does not reconcile an existing realm). Options:
   (a) `KeycloakRealmImport` for the initial realm, with later changes by re-import into a fresh realm; (b) the Keycloak
   Terraform provider or `keycloak-config-cli` as a Job for ongoing reconciliation. Default to (a) for the pilot and revisit
   if drift becomes a problem.
4. **GitHub user restriction.** Keycloak's GitHub IdP cannot filter by login natively. Candidate approach: disable
   self-registration, pre-create the `alxbl` user, and make the first-broker-login flow link-only (deny unknown users),
   keyed on the verified GitHub identity. Verify it actually blocks another GitHub account before calling it done.
5. **Secrets.** Admin bootstrap credentials, the GitHub OAuth client ID/secret and the DB credentials are Kubernetes Secrets
   created out of band. Each goes in `scripts/secrets.list` and into Proton Drive via `scripts/export-secrets`. The realm
   import references them through the operator's placeholder support, never inline.

## Phases

### 1. Prerequisites (read-only checks first)
- Argo `olm` synced; `operators` namespace and `operatorhubio-catalog` CatalogSource healthy; `kc get csv -A`.
- Sync `cnpg` (ServerSideApply); confirm the operator pod and CRDs.
- Check the apex-certificate question (decision 1).

### 2. Storage (STOP and ask before touching tachyon)
- On `core@tachyon.lan`: create `data/k8s/keycloak-db`, 10G quota, `context=none`. List existing datasets first.
- Add `infra/system/storage/base/pv-keycloak-db.yaml` (Retain, pre-bound to the CNPG claim `<cluster>-1`) and register it in
  the kustomization.
- Extend `scripts/test/storage-bindings.sh` with the keycloak database claim.
- Snapshot discipline per repo rules: no `zfs destroy`, no `zpool upgrade`.

### 3. Database and operator
- New namespace `keycloak` (add to `infra/k8s/catalog/templates/namespaces.yaml` if that is where namespaces live).
- CNPG `Cluster` for Keycloak following `pg-immich.yaml`, with the generated app secret.
- Approve the operator `InstallPlan` (manual approval), wait for the CSV `Succeeded`, then confirm the `Keycloak` CRDs.

### 4. Keycloak
- `Keycloak` CR: one instance, external DB from CNPG, hostname `segfault.me`, relative path `/auth`, proxy headers on,
  HTTP enabled behind the Gateway.
- `HTTPRoute` for `segfault.me` `/auth` to the Keycloak service (the operator creates it; confirm port and TLS mode).
- `CiliumNetworkPolicy` allowances: Gateway to Keycloak, Keycloak to Postgres, Keycloak to GitHub egress, and anything the host
  firewall needs.
- `KeycloakRealmImport` with the realm, GitHub IdP, the single allowed user and a pilot OIDC client (decision 3, 4, 5).
- Argo wiring: catalog templates for any new app, repo Secret entries if a new Helm repo is added, sync by patching `operation`.

### 5. Edge and validation
- In the `alxbl/segfault.me` repo (own worktree): configure and start the nghttpx proxy on `cortex.segfault.me`, forward
  `/auth` unchanged. Confirm whether the nghttpx setup is still needed (the brief says it may have changed).
- Validate without the SSO step: pods Ready, DB reachable, `/auth/realms/<realm>/.well-known/openid-configuration` returns the
  expected issuer through every hop (in-cluster, LAN, Cloudflare), certificates Ready, logs clean.
- Ask the user to run the GitHub login with the pilot client, watching the Keycloak logs, then test with a second GitHub
  account to prove it is denied.
- Exit criteria for Envoy Gateway work: issuer URL stable, JWKS reachable from inside the cluster, realm and client IaC
  committed, secrets exported.

### 6. Envoy Gateway (separate plan, after phase 5)
Install beside the Cilium Gateway on a second IP, attach a `SecurityPolicy` (OIDC for browsers, JWT for bearer clients) to one
low-stakes route, exempt Keycloak and health endpoints, then migrate routes. Check how OIDC and JWT interact on a single
target before relying on bearer pass-through. Write that plan when this one is done.

## Risks and rollback
- Manual InstallPlan approval is easy to forget; the operator will sit pending.
- The Keycloak operator and `fast` channel move quickly; pin the CSV version in the PR.
- A wrong hostname or relative path breaks every redirect; test the discovery document first.
- Rollback: unsync `keycloak`, remove the HTTPRoute, leave the dataset and PV (Retain). Any deletion of a bound PV/PVC or
  dataset is a STOP and ask.
- Nothing here touches existing apps; the Gateway change is one additive route.

## Deliverables
- PR(s) in `alxbl/lab` per phase; one PR in `alxbl/segfault.me` for cortex.
- Decision log (the five decisions above) in the PR descriptions.
- `scripts/secrets.list` entries and a fresh `scripts/export-secrets` run.
