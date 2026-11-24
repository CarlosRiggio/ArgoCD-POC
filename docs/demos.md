# Demos: a guided tour

Each demo is self-contained and takes 1-3 minutes. They assume `make up` has finished.
Demos marked 🤖 are fully scripted. Demos marked ✍️ involve a Git commit, because that
is the whole point of GitOps.

> Argo CD polls Git every ~60 s. To skip the wait after a push, click **Refresh** on the
> app in the UI.

| # | Demo | Shows |
|---|---|---|
| 0 | [UI tour](#0-ui-tour) | resource tree, diff, health, history |
| 1 | [Change dev through Git](#1-️-change-dev-through-git) | auto-sync, hooks, waves, config rollout, pruning |
| 2 | [Promote to prod](#2--️-promote-to-prod-manual-sync) | manual sync gate, diff review |
| 3 | [Self-heal](#3--self-heal-drift-detection) | drift detection and correction |
| 4 | [New environment from a folder](#4-️-add-and-remove-an-environment) | ApplicationSet git generator, cascade delete |
| 5 | [Rollback](#5-️-rollback) | `git revert` vs `argocd app rollback` |
| 6 | [Project guard rails](#6-️-appproject-guard-rails) | AppProject restrictions |
| 7 | [Orphaned resources](#7-orphaned-resources) | detecting things not in Git |
| 8 | [RBAC](#8--rbac-read-only-user) | local users, read-only role |
| 9 | [Argo CD upgrades itself](#9-️-argo-cd-manages-itself) | self-management |
| 10 | [CLI tour](#10-cli-tour-optional) | `argocd` CLI |

---

## 0. UI tour

1. `make info`, then open <http://localhost:8080> and log in as `admin`.
2. You should see 7 applications: `root`, `argocd`, `hello-{dev,staging,prod}`, `podinfo-{dev,prod}`.
   `hello-prod` and `podinfo-prod` are **OutOfSync** on purpose (manual sync, see demo 2).
3. Open `root`: the app-of-apps tree shows the projects, the `argocd` app and both ApplicationSets.
4. Open `hello-dev`: ConfigMap → ReplicaSet → Pods, the hook Jobs, and the health of each node.
   Click a pod for its live manifest, events and logs.
5. Open <http://localhost:8081>, <http://localhost:8082> and <http://localhost:8091> to see the running apps.

## 1. ✍️ Change dev through Git

Edit [`apps/hello/overlays/dev/kustomization.yaml`](../apps/hello/overlays/dev/kustomization.yaml):

```yaml
      - PODINFO_UI_COLOR=#805ad5             # purple
      - PODINFO_UI_MESSAGE=hello dev - v2
```

```bash
git commit -am "dev: hello v2" && git push
```

Watch `hello-dev` in the UI (Refresh to skip polling):

1. It turns **OutOfSync**, and auto-sync starts.
2. **PreSync**: `hello-db-migration` runs first (check its logs).
3. **Wave 0**: a *new* `hello-config-<newhash>` ConfigMap is created.
4. **Wave 1**: the Deployment now references the new ConfigMap, so a rolling update starts.
5. **PostSync**: `hello-smoke-test` checks the new version.
6. The old ConfigMap is **pruned**.

Refresh <http://localhost:8081>: the page is purple and says v2. Staging and prod are untouched.

## 2. 🤖 ✍️ Promote to prod (manual sync)

Prod apps have no `automated` policy, so Git changes only mark them **OutOfSync**:

1. Make a change in [`apps/hello/overlays/prod`](../apps/hello/overlays/prod/kustomization.yaml)
   (e.g. message `hello prod - v2`), commit and push.
2. In the UI, `hello-prod` → **APP DIFF** shows exactly what would change. This is the review step.
3. Promote: press **SYNC**, or run:

   ```bash
   make sync-prod          # syncs hello-prod and podinfo-prod and waits for Healthy
   ```

4. <http://localhost:8083> shows the new version.

> On a fresh cluster prod has never been synced, so `make sync-prod` is also the first deploy.

## 3. 🤖 Self-heal (drift detection)

```bash
make demo-self-heal
```

What happens:

1. `kubectl scale deploy/hello --replicas=5` in `hello-dev`. Git says 1, so the app is
   **OutOfSync**, and `selfHeal` scales it back to 1 within seconds.
2. `kubectl delete deploy/hello`. The app becomes **Missing**, and Argo CD recreates it from Git.

Try the same on `hello-prod`: it is reported **OutOfSync** but *not* repaired, because
prod has no self-heal. A human decides.

## 4. ✍️ Add and remove an environment

The `hello` ApplicationSet creates one app per folder:

```bash
cp -r apps/hello/overlays/staging apps/hello/overlays/qa
sed -i 's/staging/qa/g; s/30082/30084/' apps/hello/overlays/qa/kustomization.yaml
git add apps/hello/overlays/qa && git commit -m "add qa env" && git push
```

Within a minute `hello-qa` appears (namespace `hello-qa`, auto-synced) without you writing
any Application manifest. (30084 isn't mapped to localhost; use
`kubectl -n hello-qa port-forward svc/hello 8084:9898` to open it.)

Remove it again:

```bash
git rm -r apps/hello/overlays/qa && git commit -m "remove qa env" && git push
```

The ApplicationSet deletes `hello-qa`, and thanks to the `resources-finalizer` its
Deployment, Service, etc. are deleted too. (The empty namespace stays: Argo CD doesn't
delete namespaces it created with `CreateNamespace=true`.)

## 5. ✍️ Rollback

**The GitOps way: `git revert`.**

```bash
git revert --no-edit HEAD && git push   # undo demo 1
```

Auto-sync deploys the previous state, and the history stays truthful.

**The emergency way: Argo CD history.** Each app's *HISTORY AND ROLLBACK* lists past synced revisions.

- On `hello-prod` (manual sync), rolling back works. The app then shows OutOfSync,
  because Git and cluster now differ, until Git is fixed too.
- On `hello-dev` it is **refused**: *"rollback cannot be initiated when auto-sync is enabled"*.
  Auto-sync would undo it straight away. That refusal is a useful interview talking point.

## 6. ✍️ AppProject guard rails

The `apps` project forbids `ResourceQuota`. Try to sneak one into dev:

```bash
cat > apps/hello/overlays/dev/quota.yaml <<'EOF'
apiVersion: v1
kind: ResourceQuota
metadata:
  name: sneaky-quota
spec:
  hard:
    pods: "100"
EOF
sed -i 's#  - ../../base#  - ../../base\n  - quota.yaml#' apps/hello/overlays/dev/kustomization.yaml
git add -A && git commit -m "try a quota" && git push
```

`hello-dev`'s sync **fails** with *"resource :ResourceQuota is not permitted in project apps"*.
The same happens if an app of this project targets e.g. `kube-system`.
Revert with `git revert --no-edit HEAD && git push`.

## 7. Orphaned resources

Create something by hand that is not in Git:

```bash
kubectl -n hello-dev create configmap created-by-hand --from-literal=foo=bar
```

The `apps` project has `orphanedResources.warn: true`, so `hello-dev` shows an
**orphaned resources** warning, and the UI can list them (filter *Orphaned*). Clean up:
`kubectl -n hello-dev delete configmap created-by-hand`.

## 8. 🤖 RBAC: read-only user

```bash
make demo-rbac
```

1. Sets the password of the local user `viewer` (`viewer123`). It's declared in
   `configs.cm.accounts.viewer` and bound to `role:readonly` in `configs.rbac.policy.csv`.
2. Logs in through the REST API, lists the apps (allowed), and tries to sync `hello-prod`, which is
   **denied with HTTP 403**.

Also try it in the UI: log out, log in as `viewer` / `viewer123`. Everything is visible,
and the SYNC/DELETE buttons fail with *permission denied*.

## 9. ✍️ Argo CD manages itself

Configuration change: edit [`bootstrap/argocd-values.yaml`](../bootstrap/argocd-values.yaml),
e.g. enable the status badge:

```yaml
configs:
  cm:
    statusbadge.enabled: true
```

Push. The `argocd` app syncs and Argo CD reconfigures itself. Badge URL:
<http://localhost:8080/api/badge?name=hello-dev>.

Upgrade: bump `targetRevision` of the chart in [`argocd/apps/argocd.yaml`](../argocd/apps/argocd.yaml)
(and `ARGOCD_CHART` in the Makefile, so fresh installs match). Push, and Argo CD rolls out its
own new version. No `helm upgrade` needed.

## 10. CLI tour (optional)

```bash
make cli                                   # downloads bin/argocd (pinned v3.6.2)
bin/argocd login localhost:8080 --plaintext --grpc-web --username admin --password "$(make -s password)"

bin/argocd app list
bin/argocd app get hello-dev               # status, resources, sync result
bin/argocd app diff hello-prod             # what a sync would change
bin/argocd app sync hello-prod             # manual sync
bin/argocd app history hello-prod
bin/argocd app rollback hello-prod 1       # roll back to history id 1
bin/argocd proj get apps                   # project guard rails
bin/argocd appset list
bin/argocd account list                    # admin + viewer
bin/argocd account can-i sync applications 'apps/*'   # RBAC check
```
