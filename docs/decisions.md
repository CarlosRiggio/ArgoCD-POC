# Design decisions (and what would change in production)

Short, ADR-style notes on *why* the repo looks the way it does.

## Local cluster: kind

- **Chosen:** [kind](https://kind.sigs.k8s.io/). Upstream Kubernetes in Docker, multi-node,
  the de-facto standard for testing Kubernetes tooling and for CI. The same
  `cluster/kind-config.yaml` runs on a laptop and in GitHub Actions.
- **Alternatives:** k3d (faster start, but k3s rather than upstream Kubernetes),
  minikube (VM-based, heavier).

## Exposing services: NodePort + kind port mappings, no ingress

- kind maps NodePorts `30080-30092` to `localhost:8080-8092`. There's no ingress controller
  to install, no `/etc/hosts` edits and no `port-forward` processes to keep alive.
- ingress-nginx (the old default) was retired in 2026. A production setup would use a
  Gateway API implementation (Envoy Gateway, Cilium, Traefik…) with TLS, which is out of scope here.

## Installing Argo CD: Helm once, then self-managed

- **Bootstrap problem:** something must install Argo CD before Argo CD can install anything.
- `make argocd` runs `helm upgrade --install` **once**. The `argocd` Application then
  adopts the same release (same chart version, same values file, same `releaseName`) and
  Argo CD manages itself from Git from then on.
- One values file ([`bootstrap/argocd-values.yaml`](../bootstrap/argocd-values.yaml)) is used by
  both the bootstrap and the self-managing app, so they can't drift apart.
- `ServerSideApply=true`: Argo CD's CRDs exceed the 256 KB `last-applied-configuration` annotation
  limit of client-side apply.
- `prune: false` and no finalizer on the `argocd` app: a bad commit must never be able to delete Argo CD itself.

## Repo structure: app-of-apps for bootstrap, ApplicationSets for workloads

- `root` (app-of-apps) is the only hand-applied manifest. It brings up projects, Argo CD itself and the ApplicationSets.
- ApplicationSets generate the workload Applications, so adding an environment is a folder or a list entry, not
  another hand-written Application.
- This hybrid is the most common community pattern: app-of-apps for bootstrapping,
  ApplicationSets for scale.
- `root` lives in the `default` project because the custom projects don't exist when it's first applied.
  In production you would also lock down `default`.

## Environments: Kustomize overlays (folders), not branches

- One branch (`main`), one folder per environment. Branch-per-environment causes merge drift and
  is a recognised GitOps anti-pattern.
- Promotion = changing the next environment's overlay (by hand here. In real life a PR, often opened
  by CI or a tool like Kargo).
- **dev/staging auto-sync, prod manual sync**: a cheap, visible promotion gate.

## Two config tools on purpose

- `hello` = **Kustomize** (in-house app, base + overlays).
- `podinfo` = **Helm**, a third-party chart pinned to a version, values kept in our repo through
  **multi-source** Applications (no forked charts, no vendored chart copies).

## Sync waves and hooks on the demo app

- PreSync migration Job, then ConfigMap (wave 0), then Deployment/Service (wave 1), then PostSync smoke test.
  This mirrors a real release: migrate the schema, roll out, verify.
- `configMapGenerator` hash suffixes make config changes roll pods automatically, and pruning removes old ConfigMaps.

## Security choices for a *local* POC

| Here | Production |
|---|---|
| `server.insecure: true` (HTTP) | TLS at the gateway/ingress, or Argo CD's own TLS |
| local `admin` + `viewer` users | `admin.enabled: false`, SSO (Dex/OIDC) groups mapped to roles |
| Viewer password set imperatively by `make viewer`, never committed | Same principle: no secrets in Git, ever. Use External Secrets Operator / Sealed Secrets / SOPS |
| Public repo, no credentials | Private repo with a read-only deploy key or GitHub App, declared as a repository Secret |
| Polling Git every ~60 s | GitHub webhook → instant sync, longer polling interval |
| Single cluster | Hub-and-spoke: one Argo CD managing many clusters, cluster generator in ApplicationSets |
| No resource quotas | Quotas/LimitRanges per namespace, owned by the platform project |

## Versions are pinned everywhere

Argo CD chart `10.19.0` (Argo CD v3.6.2), podinfo chart/image `6.17.0`, `busybox:1.37.0`, the kind
node image (via kind 0.32 → Kubernetes v1.36). Nothing floats on `latest`, so the POC is
reproducible, and upgrades are explicit commits that Argo CD rolls out.

## CI

- **lint** (every push/PR): renders everything with `kustomize`/`helm` and validates the output
  against Kubernetes + Argo CD CRD schemas (kubeconform), so broken YAML is caught before Argo CD sees it.
- **e2e** (pushes to `main`): creates the same kind cluster, bootstraps, waits for convergence,
  promotes to prod and runs the self-heal and RBAC demos as tests.
