#!/usr/bin/env bash
# Offline validation: render every manifest exactly the way Argo CD would
# (kustomize build / helm template) and validate it against the Kubernetes
# and Argo CD CRD JSON schemas with kubeconform.
#
# Catches broken YAML, bad Kustomize patches, wrong Helm values and invalid
# Argo CD resources BEFORE they reach Git/Argo CD. Runs locally (`make lint`)
# and in CI (.github/workflows/ci.yaml).
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."

OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

# Chart versions are read from the Argo CD manifests so there is one source of truth.
PODINFO_CHART=$(grep -m1 'targetRevision: [0-9]' argocd/apps/podinfo-appset.yaml | awk '{print $2}')
ARGOCD_CHART=$(grep -m1 'targetRevision: [0-9]' argocd/apps/argocd.yaml | awk '{print $2}')

info "Rendering Kustomize overlays (hello)"
for dir in apps/hello/overlays/*/; do
  env=$(basename "$dir")
  kubectl kustomize "$dir" > "$OUT/hello-$env.yaml"
  ok "hello-$env"
done

info "Rendering Helm charts"
helm repo add podinfo https://stefanprodan.github.io/podinfo --force-update >/dev/null
helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null
for values in apps/podinfo/values-*.yaml; do
  env=${values##*/values-}; env=${env%.yaml}
  [[ "$env" == "common" ]] && continue
  helm template podinfo podinfo/podinfo --version "$PODINFO_CHART" \
    -f apps/podinfo/values-common.yaml -f "$values" > "$OUT/podinfo-$env.yaml"
  ok "podinfo-$env (chart $PODINFO_CHART)"
done
helm template argocd argo/argo-cd --version "$ARGOCD_CHART" -n argocd \
  -f bootstrap/argocd-values.yaml > "$OUT/argocd.yaml"
ok "argocd (chart $ARGOCD_CHART)"

info "Collecting Argo CD resources (projects, apps, appsets, root)"
for f in bootstrap/root-app.yaml argocd/projects/*.yaml argocd/apps/*.yaml; do
  printf -- '---\n'; cat "$f"   # explicit document separator between files
done > "$OUT/argocd-resources.yaml"
ok "argocd-resources"

if ! command -v kubeconform >/dev/null; then
  warn "kubeconform not installed: rendering succeeded, schema validation skipped."
  warn "Install it from https://github.com/yannh/kubeconform/releases to validate schemas."
  exit 0
fi

info "Validating schemas with kubeconform"
# Argo CD's own chart is validated without -strict: it is upstream-maintained
# and may legitimately use fields newer than the published schemas.
kubeconform -summary -strict -ignore-missing-schemas=false \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  "$OUT"/hello-*.yaml "$OUT"/podinfo-*.yaml "$OUT/argocd-resources.yaml"
kubeconform -summary -ignore-missing-schemas \
  -schema-location default "$OUT/argocd.yaml"
ok "All manifests are valid."
