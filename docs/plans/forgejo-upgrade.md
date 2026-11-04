# Forgejo upgrade plan

Procedure to move segv's Forgejo to a new version, with a ZFS rollback path. `<VER>` is the target Forgejo release (for example
`17.0.1`), `<OLD>` the version running now.

Conventions: `STOP and ask` = the user says go in the conversation first. Never `zfs destroy` or `zfs rollback -r` without an
explicit go for the named snapshots, after listing them and any holds.

## Decide first
- Forgejo's majors are not chart majors: chart `forgejo` has its own numbering. Check which Forgejo the newest chart ships (its
  appVersion). If it ships `<VER>`, bump `targetRevision` instead of using `image.tag`.
- Only LTS releases get long support. Check the support end dates of `<OLD>` and `<VER>` on forgejo.org/releases. A non-LTS
  target means another upgrade within months.
- Do not skip a major that has a required migration. Read the upgrade guide for every major between `<OLD>` and `<VER>`.
- `image.tag` defaults to the chart appVersion; with `image.rootless: true` the chart appends `-rootless`. Render the chart
  with `--set image.tag=<VER>` and check that only the image references change. Check the tag exists in
  `code.forgejo.org/forgejo/forgejo`.

## Layout
- `forgejo` Application: chart `forgejo` (`infra/k8s/catalog/templates/forgejo.yaml`), Deployment `forgejo`, one replica,
  data on dataset `data/k8s/forgejo` (PV `forgejo`).
- `forgejo-database` Application: kustomize `infra/k8s/forgejo`: CNPG Cluster `forgejo-database` (1 instance) on dataset
  `data/k8s/forgejo-db` (PV `forgejo-db`) and StatefulSet `forgejo-runner` (3 replicas).
- Neither Application has auto-sync, so a `kubectl scale` sticks until the next sync. A sync resets replicas to the manifests.
- Datasets live on `core@tachyon.lan`. `zfs snapshot`, `hold`, `release` and `rollback` need `sudo -n` there; `core` has no
  delegation. Set `KUBECONFIG` to the absolute path of `main/infra/clusters/segv/kube.conf` in a worktree.
- There is no `argocd` or `velero` CLI: use `kubectl` on the Application and on `backups.velero.io` (namespace `system`).

## Before
1. Read the full release notes of every major from `<OLD>` to `<VER>`, not only the announcement. Look for removed or renamed
   settings, mirror and webhook changes, protected names, runner version requirements (the runner must meet the new minimum)
   and breaking API or workflow changes. Update this file if they disagree.
2. `zfs list -t snapshot -r data/k8s/forgejo data/k8s/forgejo-db` and `zfs holds` on each. Use a snapshot name that does not
   exist yet. A rollback to anything but the newest snapshot needs `-r` and destroys the newer ones. STOP and ask if that is
   the case.
3. Confirm the latest Velero backup of `code` completed. It is the fallback if the ZFS rollback goes wrong.
4. List the instance's webhooks and mirrors through the admin API (the credential is in Secret `forgejo-admin`; read it inside
   a script, never on a command line). Announce the downtime: nothing may be pushed between the snapshot and the end of the
   trial, or the rollback loses it.

## Snapshot
1. Scale `statefulset/forgejo-runner` and `deployment/forgejo` (namespace `code`) to 0. Wait for the pods to go.
2. Hibernate the database: annotate Cluster `forgejo-database` with `cnpg.io/hibernation=on` and wait for the pod to go.
3. Snapshot both datasets as `pre-forgejo<major>`: `data/k8s/forgejo-db@...` and `data/k8s/forgejo@...`. Snapshot the data
   dataset as well, not only the database: a database-only rollback would leave repositories and queues inconsistent. Place a
   `keep` hold on both.
4. Remove the hibernation annotation and wait for the database pod itself to be Ready (the Cluster condition can be stale).

## Trial
1. Patch the `forgejo` Application with the helm parameter `image.tag=<VER>` (not committed to git) and sync it with
   `ServerSideApply=true`. Per the repo rules: hard-refresh, patch `operation`, and wait on the new `startedAt`. The sync brings
   `forgejo` back to one replica.
2. Watch the pod. The init containers and the database migration run first; read the log for migration and config errors.
3. Scale `forgejo-runner` back to 3 and check that they register.
4. Verify. The user does the Keycloak SSO login by hand: ask for it. Everything else can be scripted with the break-glass
   admin: version and OIDC auth source (`forgejo admin auth list`, and the login redirect to Keycloak), git over SSH on
   `10.3.0.2` with a throwaway key and repository (delete both afterwards), a push and a clone, a CI run on the runner
   (`runs-on: docker`), a sync of the `aur` mirror, the web UI, and `forgejo doctor`.
   - `forgejo doctor check --all` fails on its `paths` check because `/data/log` has never existed on this volume. Run the
     rest with `--run <name>`, leaving out `paths`, `gc-lfs` and `delete-orphaned-repos`. Pre-existing orphaned rows are known.

## If it works
Commit the change (`image.tag` in the catalog template, or the chart `targetRevision`) and open a PR. After it is merged and
synced, remove the manual `image.tag` parameter from the live Application (JSON patch `remove` on
`/spec/source/helm/parameters`) and sync again; the pod does not restart. Drop `image.tag` from the template once a chart ships
this version as its appVersion. Keep the snapshots until the user decides; release the holds and destroy them only on an
explicit go.

## If it does not (rollback)
After the new version migrates the database, the old one cannot read it, so restore the volumes; do not just change the tag.
1. Scale `statefulset/forgejo-runner` and `deployment/forgejo` to 0.
2. Hibernate `forgejo-database` and wait for its pod to go.
3. `zfs rollback` both datasets to the snapshot (pre-authorized only when the user said so and no newer snapshot exists;
   otherwise STOP and ask). If newer snapshots exist, `-r` destroys them, so list them first.
4. Remove the hibernation annotation and wait for the pod to be Ready.
5. Remove the `image.tag` helm parameter from the `forgejo` Application and sync. This restores the chart's default image and
   one replica. Scale `forgejo-runner` back to 3.
6. Verify as above. Wait for a chart that ships the target and rerun this plan.

If the rollback itself fails: restore from the Velero backup (`forgejo-database` carries a `pg_dump` at `backup/app.dump` next
to its data; restore with `pg_restore`).

## Log
### 2026-11-04: 15.0.11 to 17.0.1 (worked)
- Chart 17.3.2 (appVersion 15.0.11) with `image.tag=17.0.1`. Migrations v16a to v17a ran cleanly, and the `app.ini` the chart
  generates worked unchanged. The release notes added: mirrors and migrations over `http://` and `git://` are refused, config
  durations are parsed strictly, `actor` is a protected username, action-run webhooks are deprecated (the instance had none).
- Verified: Keycloak SSO login, OIDC auth source kept, SSH push and clone, a CI run, `aur` mirror sync, web UI. Harmless
  warnings: `package_cleanup_rule` `*_last_download_days` are BIGINT in the database and INTEGER in the struct.
- The first attempt stopped at the snapshot (permission denied for `core`) and everything was restored; nothing had changed.
- Committed as `image.tag: 17.0.1`. 17.0 is not an LTS (supported until 2027-01-28); 15.0 is (until 2027-07-15).
