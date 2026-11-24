# Setup & troubleshooting

## Prerequisites

| Tool | Tested version | Why |
|---|---|---|
| Docker | 29.x | kind runs Kubernetes nodes as Docker containers |
| [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) | 0.32 | the local Kubernetes cluster (node image v1.36) |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | 1.36 | talk to the cluster (also provides `kubectl kustomize`) |
| [Helm](https://helm.sh/docs/intro/install/) | 3.21 | first install of Argo CD + rendering charts in `make lint` |
| make, curl, jq | any | glue |
| argocd CLI | 3.6.2 | **optional**: `make cli` downloads it into `./bin` |
| [kubeconform](https://github.com/yannh/kubeconform) | 0.7 | **optional**: schema validation in `make lint` (always runs in CI) |

Hardware: ~4 GB of free RAM and 2+ CPUs are plenty.

Run `make check` to verify everything is in place.

### Windows / WSL2

kind needs a Docker daemon reachable from inside your WSL distro:

1. Install **Docker Desktop** on Windows.
2. Docker Desktop → *Settings* → *Resources* → *WSL integration* → enable your distro (e.g. *Ubuntu-24.04*) → *Apply & restart*.
3. In WSL: `docker info` must work.

The ports (`localhost:8080`, …) are reachable from both WSL and your Windows browser.

### Linux / macOS

Any Docker-compatible engine works (Docker Engine, Docker Desktop, OrbStack, Colima).

## Ports used on localhost

| Port | What |
|---|---|
| 8080 | Argo CD UI + API |
| 8081 / 8082 / 8083 | hello dev / staging / prod |
| 8091 / 8092 | podinfo dev / prod |

They are bound to `127.0.0.1` only. If one is already taken, change `hostPort` in
[`cluster/kind-config.yaml`](../cluster/kind-config.yaml) and recreate the cluster.

## Using a fork

All manifests point at `https://github.com/CarlosRiggio/ArgoCD-POC.git`. If you fork
the repo, replace that URL everywhere (it must be a **public** repo, or you must add a
[repository credential](https://argo-cd.readthedocs.io/en/stable/user-guide/private-repositories/)):

```bash
grep -rl 'CarlosRiggio/ArgoCD-POC' bootstrap argocd | xargs sed -i 's#CarlosRiggio/ArgoCD-POC#<you>/<your-repo>#g'
```

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `make check` → Docker not reachable | Start Docker Desktop / enable WSL integration (see above). |
| `kind create cluster` → port is already allocated | Something already listens on 8080-8092. Stop it or change `hostPort`. |
| Apps stuck in `Unknown` / `ComparisonError` | Argo CD can't read the repo. Is it public? Is the URL right? `kubectl -n argocd get app <name> -o yaml` → `status.conditions`. |
| A change pushed to Git isn't deployed yet | Argo CD polls Git every ~60 s. Click **Refresh** in the UI to force it. |
| `hello-prod` / `podinfo-prod` are `OutOfSync` | Expected! Prod uses manual sync. Run `make sync-prod`. |
| `make demo-rbac` → login failed | Run `make viewer` first (it sets the viewer's password). |
| Pods `ImagePullBackOff` | No internet / Docker Hub rate limit. Wait and retry, or `kind load docker-image <image>`. |
| Start from scratch | `make down && make up` |

Useful commands:

```bash
make status                                         # apps and appsets
kubectl -n argocd get app hello-dev -o yaml         # full status, conditions, history
kubectl -n argocd logs deploy/argocd-repo-server    # manifest rendering errors
kubectl -n argocd logs sts/argocd-application-controller   # sync / health errors
kubectl -n argocd logs deploy/argocd-applicationset-controller  # appset generation errors
```
