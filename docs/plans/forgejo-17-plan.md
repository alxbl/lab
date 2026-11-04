# Forgejo 17 trial plan

Tracks #148. Forgejo 17.0 was released on 2026-10-15; segv runs 15.0.11 (LTS) from chart `forgejo` 17.3.2, whose appVersion is
15.0.11. The chart's major (17) is its own numbering and has nothing to do with Forgejo's. As of 2026-11-03 no chart ships
Forgejo 17, so this plan runs the 17 image on the current chart through `image.tag` and rolls back if it does not work.

Run on 2026-11-04; it worked and 17.0.1 is kept (see Outcome). Conventions: `STOP and ask` = the user says go in the conversation first. Never `zfs destroy` or
`zfs rollback -r` without an explicit go for the named snapshots, after listing them and any holds.

## Decision first
17.0 is not an LTS: supported until 2027-01-28. 15.0 is the LTS: supported until 2027-07-15. Staying on 17 means another upgrade
within months. 16.0 is already end of life (2026-10-29), so going through it is not an option and no rule requires it: the
upgrade guide has no note about skipping majors and lists no required migration or config change for 16 or 17.

## What the research found
- `image.tag` exists (default: the chart appVersion). With `image.rootless: true` the chart appends `-rootless`. Rendering chart
  17.3.2 with `--set image.tag=17.0.1` changes only the four image references (three init containers and the main one) to
  `code.forgejo.org/forgejo/forgejo:17.0.1-rootless`. That tag exists in the registry (also `17.0.0`).
- Untested: the chart's generated `app.ini` has only been exercised against Forgejo 15.
- Breaking changes in 16 (from the release article, not the full `16.0.0.md`; read that before the trial):
  - Mirrors: git no longer follows redirects, so a mirror of a renamed or transferred Forgejo repository fails. Check mirrors
    that pull from other Forgejo instances. The GitHub `aur` mirror should be unaffected.
  - `REVERSE_PROXY_TRUSTED_PROXIES` no longer defaults to `*` in containers. Not used: sign-in is OIDC through Keycloak.
  - Skipped Actions checks now report `skipped`, not `success`. Review branch rules or workflows that depend on it.
  - Optional: delete the per-repository example hooks (upgrade guide, hooks section).
- 17: relative links in rendered documents resolve from the repository root; action-run webhooks are deprecated and are not
  migrated (list the instance's webhooks first). Optional: delete unused `pulls/*.patch` files.
- Runner is 13.2.1, which meets the 13.2 minimum for job summaries.
- Read in full on 2026-11-04, additionally: 17 refuses mirrors and migrations over `http://` and `git://` (the `aur` mirror is
  https); config durations are parsed strictly; `actor` is a protected username.

## Layout
- `forgejo` Application: chart `forgejo` 17.3.2 (`infra/k8s/catalog/templates/forgejo.yaml`), Deployment `forgejo`, one replica,
  data on dataset `data/k8s/forgejo` (PV `forgejo`).
- `forgejo-database` Application: kustomize `infra/k8s/forgejo`: CNPG Cluster `forgejo-database` (1 instance) on dataset
  `data/k8s/forgejo-db` (PV `forgejo-db`) and StatefulSet `forgejo-runner` (3 replicas).
- Neither Application has auto-sync, so a `kubectl scale` sticks until the next sync. A sync resets replicas to the manifests.
- Datasets live on `core@tachyon.lan`. Set `KUBECONFIG` to the absolute path of `main/infra/clusters/segv/kube.conf` in a worktree.

## Before
1. Read `16.0.0.md` and the 17.0 release notes in full; update this file if they disagree.
2. On the node (`core@tachyon.lan`; `zfs snapshot`, `hold` and `rollback` need `sudo -n`, `core` has no delegation):
   `zfs list -t snapshot -r data/k8s/forgejo data/k8s/forgejo-db` and `zfs holds` on each. A rollback to anything but
   the newest snapshot needs `-r` and destroys the newer ones. STOP and ask if that is the case.
3. Confirm the latest Velero backup of `code` completed (`kubectl -n system get backups.velero.io`; there is no `velero` CLI). It is the fallback if the ZFS rollback goes wrong.
4. List the instance's webhooks and its mirrors. Announce the downtime: nothing may be pushed between the snapshot and the
   end of the trial, or the rollback loses it.

## Snapshot
1. Scale `statefulset/forgejo-runner` and `deployment/forgejo` (namespace `code`) to 0. Wait for the pods to go.
2. Hibernate the database: annotate Cluster `forgejo-database` with `cnpg.io/hibernation=on` and wait for the pod to go.
   (An atomic ZFS snapshot of a running Postgres is crash-consistent too, but a clean stop costs nothing.)
3. Snapshot both datasets as `pre-forgejo17`: `data/k8s/forgejo-db@pre-forgejo17` and `data/k8s/forgejo@pre-forgejo17`. Snapshot
   the data dataset as well, not only the database: 17 also writes to repositories and queues, and a database-only rollback
   would leave them inconsistent. Place a `keep` hold on both, as the cutover snapshots have.
4. Remove the hibernation annotation and wait for the cluster to be `Ready`.

## Trial
1. Patch the `forgejo` Application with the helm parameter `image.tag=17.0.1` (not committed to git) and sync it. Per the
   repo rules: hard-refresh, patch `operation`, and wait on the new `startedAt`. The sync brings `forgejo` back to one replica.
2. Watch the pod. The init containers and the database migration run first; read the log for migration errors.
3. Scale `forgejo-runner` back to 3.
4. Verify: sign-in through Keycloak, git over SSH on `10.3.0.2`, a push and a clone, a CI run on the runner, a sync of the `aur`
   mirror, the web UI, then `forgejo doctor check --all` in the pod.

## If it works
Commit `image.tag: 17.0.1` to the catalog template and open a PR. Drop it once a chart ships Forgejo 17 as its appVersion. Keep
the `@pre-forgejo17` snapshots until the user decides; release the holds and destroy them only on an explicit go.

## If it does not (rollback)
After 17 migrates the database, 15 cannot read it, so restore the volumes; do not just change the tag back.
1. Scale `statefulset/forgejo-runner` and `deployment/forgejo` to 0.
2. Hibernate `forgejo-database` and wait for its pod to go.
3. STOP and ask: `zfs rollback` both datasets to `@pre-forgejo17`. If newer snapshots exist, `-r` destroys them, so list them first.
4. Remove the hibernation annotation and wait for `Ready`.
5. Remove the `image.tag` helm parameter from the `forgejo` Application and sync. This restores the chart's default image
   (15.0.11) and one replica. Scale `forgejo-runner` back to 3.
6. Verify as above. Wait for a chart whose appVersion is 17 and rerun this plan with it.

If the rollback itself fails: restore from the Velero backup (`forgejo-database` carries a `pg_dump` at
`backup/app.dump` next to its data; restore with `pg_restore`).

## Outcome (2026-11-04)
- Forgejo 17.0.1 ran on chart 17.3.2 through `image.tag`; migrations v16a to v17a ran cleanly and the `app.ini` the chart
  generates worked unchanged. Verified: Keycloak SSO login (by hand), OIDC auth source kept, SSH push and clone on `10.3.0.2`,
  a CI run, `aur` mirror sync, web UI. No webhooks existed. `image.tag: 17.0.1` was committed to the catalog template.
- `forgejo doctor check --all` fails on its `paths` check: `/data/log` has never existed on this volume. Run the other checks
  with `--run <name>` (not the `paths`, `gc-lfs` and `delete-orphaned-repos` ones); they were clean apart from old orphaned rows.
- Harmless log warnings: `package_cleanup_rule` `*_last_download_days` are BIGINT in the database and INTEGER in the struct.
- The first attempt stopped at the snapshot (permission denied) and everything was restored; nothing had changed.
- Snapshots `@pre-forgejo17` (hold `keep`) are kept until the user decides.
