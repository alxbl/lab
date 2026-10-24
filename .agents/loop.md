---
# Agent loop settings for this repo. Contract: ~/.config/agents/skills/loop-setup/PROTOCOL.md
base: main
branch: "<type>/<slug>"
commits: conventional
validate:
  - .worktrees/<branch>/scripts/test/<name>.sh, one call per script, when scripts/ or scripts/test/ change
  - ansible-playbook --syntax-check -i .worktrees/<branch>/ansible/hosts .worktrees/<branch>/ansible/playbook.yml
  - kubectl kustomize .worktrees/<branch>/<changed kustomize dir>
  - helm lint .worktrees/<branch>/<changed chart>
  - helm template .worktrees/<branch>/<changed chart>
  - terraform fmt -check .worktrees/<branch>/<changed .tf file>
environments:
  segv:
    access: read-only
    how: kubectl --kubeconfig infra/clusters/segv/kube.conf <get|describe|logs> [flags], verb first (e.g. `... get -n argocd applications`); flags before the verb match no allow rule. Never terraform, helm install/upgrade, or scripts/bootstrap.sh.
  dev:
    access: none
    how: infra/clusters/dev/dev.conf, always passed with --kubeconfig. Not available to loops.
review:
  extra:
    - dev/vm.sh, dev/dnsmasq.conf, infra/clusters/dev/dev.tf and infra/clusters/dev/butane/hosts.yaml keep node MACs and IPs in sync
    - Cilium chart stays pinned at 1.18.14; the Typhoon git ref is unchanged; Istio, Calico and OpenEBS are not reintroduced
    - scripts/pacstrap.sh is not moved or renamed
    - No secrets, kubeconfigs (*.conf), terraform state or private PKI are added
    - A new workload has a catalog template plus its manifests; changes to charts/aquisition do not assume auto-sync
    - Changes are unit tested (scripts/test/ for scripts)
---
# Workflow notes

- `CLAUDE.md` is binding. Docs (`README.md`, `DEVELOPMENT.md`, `scripts/README.md`) lag the code; trust scripts and manifests and report drift.
- Source `.env` first (zsh). It exports `KUBECONFIG` for segv.
- Validation never touches live systems. `terraform fmt -check -recursive infra` already fails on main for `dev.tf` and `segv.tf`, so check only the files you change.
- Check image tags and release notes with WebFetch or WebSearch; `curl` is not allowed.
- Apps track `HEAD` of `main`; changes take effect only after the human merges and syncs.
