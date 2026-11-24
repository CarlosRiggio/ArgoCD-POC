# Argo CD POC - every command you need.  Run `make` (or `make help`) to list them.
#
# Quick start:   make up      -> cluster + Argo CD + all apps, ready in ~3-5 min
# Tear down:     make down

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

CLUSTER_NAME   := argocd-poc
ARGOCD_NS      := argocd
# Helm chart 10.19.0 == Argo CD v3.6.2 (keep in sync with argocd/apps/argocd.yaml)
ARGOCD_CHART   := 10.19.0
# argocd CLI version downloaded by `make cli`
ARGOCD_VERSION := v3.6.2
ARGOCD_URL     := http://localhost:8080

##@ Lifecycle

.PHONY: up
up: check cluster argocd bootstrap wait info ## Create EVERYTHING: cluster, Argo CD, apps

.PHONY: down
down: ## Delete the kind cluster (and everything in it)
	kind delete cluster --name $(CLUSTER_NAME)

.PHONY: check
check: ## Verify required tools are installed and Docker is running
	@for t in docker kind kubectl helm jq curl; do \
	  command -v $$t >/dev/null || { echo "✘ missing tool: $$t (see docs/setup.md)"; exit 1; }; \
	done
	@docker info >/dev/null 2>&1 || { echo "✘ Docker is not running / not reachable"; exit 1; }
	@echo "✔ all prerequisites found"

.PHONY: cluster
cluster: ## 1) Create the local kind cluster (idempotent)
	@if kind get clusters | grep -qx $(CLUSTER_NAME); then \
	  echo "✔ cluster $(CLUSTER_NAME) already exists"; \
	else \
	  kind create cluster --config cluster/kind-config.yaml; \
	fi
	@kubectl config use-context kind-$(CLUSTER_NAME) >/dev/null

.PHONY: argocd
argocd: ## 2) Install Argo CD with Helm (bootstrap only; Argo CD manages itself afterwards)
	helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null
	helm upgrade --install argocd argo/argo-cd \
	  --version $(ARGOCD_CHART) \
	  --namespace $(ARGOCD_NS) --create-namespace \
	  --values bootstrap/argocd-values.yaml \
	  --wait --timeout 10m

.PHONY: bootstrap
bootstrap: ## 3) Apply the root app-of-apps (the ONLY manifest applied by hand)
	kubectl apply -f bootstrap/root-app.yaml

.PHONY: wait
wait: ## Wait until all auto-synced apps are Synced + Healthy
	@scripts/wait-for-apps.sh 600

##@ Access

.PHONY: info
info: ## Print URLs and the admin password
	@echo
	@echo "  Argo CD UI     $(ARGOCD_URL)   (user: admin, password: $$(source scripts/lib.sh && admin_password))"
	@echo "  hello dev      http://localhost:8081"
	@echo "  hello staging  http://localhost:8082"
	@echo "  hello prod     http://localhost:8083   (manual sync -> make sync-prod)"
	@echo "  podinfo dev    http://localhost:8091"
	@echo "  podinfo prod   http://localhost:8092   (manual sync -> make sync-prod)"
	@echo

.PHONY: password
password: ## Print the Argo CD admin password
	@source scripts/lib.sh && admin_password && echo

.PHONY: status
status: ## Show Argo CD Applications and ApplicationSets
	@kubectl -n $(ARGOCD_NS) get applicationsets
	@echo
	@kubectl -n $(ARGOCD_NS) get applications

.PHONY: cli
cli: ## (optional) Download the pinned argocd CLI into ./bin
	@mkdir -p bin
	curl -sSL -o bin/argocd https://github.com/argoproj/argo-cd/releases/download/$(ARGOCD_VERSION)/argocd-linux-amd64
	@chmod +x bin/argocd
	@bin/argocd version --client --short
	@echo "Log in with:  bin/argocd login localhost:8080 --plaintext --grpc-web --username admin --password \$$(make -s password)"

##@ Demos (see docs/demos.md)

.PHONY: sync-prod
sync-prod: ## Promote: manually sync the prod apps (hello-prod, podinfo-prod)
	@scripts/sync-prod.sh

.PHONY: demo-self-heal
demo-self-heal: ## Break hello-dev by hand and watch Argo CD repair it
	@scripts/demo-self-heal.sh

.PHONY: viewer
viewer: ## Set a password for the read-only 'viewer' user
	@scripts/set-viewer-password.sh

.PHONY: demo-rbac
demo-rbac: viewer ## Show that 'viewer' can list apps but cannot sync them
	@scripts/demo-rbac.sh

##@ Validation (also run in CI)

.PHONY: lint
lint: ## Render every app offline (kustomize + helm) and validate the schemas
	@scripts/validate.sh

##@ Help

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage: make \033[36m<target>\033[0m\n"} \
	  /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2 } \
	  /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)
	@echo
