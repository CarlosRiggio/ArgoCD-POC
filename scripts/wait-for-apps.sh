#!/usr/bin/env bash
# Wait until Argo CD has created every expected Application and every
# AUTO-synced one is Synced + Healthy. Manual-sync (prod) apps only need to exist.
#
# Usage: scripts/wait-for-apps.sh [timeout_seconds]
source "$(dirname "$0")/lib.sh"

TIMEOUT=${1:-600}
EXPECTED=(root argocd hello-dev hello-staging hello-prod podinfo-dev podinfo-prod)

info "Waiting up to ${TIMEOUT}s for Argo CD applications to converge..."
deadline=$((SECONDS + TIMEOUT))
while true; do
  pending=()
  for app in "${EXPECTED[@]}"; do
    if ! kubectl -n "$NS" get application "$app" >/dev/null 2>&1; then
      pending+=("$app(missing)"); continue
    fi
    auto=$(kubectl -n "$NS" get application "$app" -o jsonpath='{.spec.syncPolicy.automated}')
    [[ -z "$auto" ]] && continue   # manual app: existing is enough
    read -r sync health <<<"$(app_status "$app")"
    [[ "$sync" == "Synced" && "$health" == "Healthy" ]] || pending+=("$app(${sync:-?}/${health:-?})")
  done

  if [[ ${#pending[@]} -eq 0 ]]; then
    ok "All auto-synced applications are Synced and Healthy."
    kubectl -n "$NS" get applications
    exit 0
  fi
  if (( SECONDS > deadline )); then
    kubectl -n "$NS" get applications || true
    fail "Timed out. Still pending: ${pending[*]}"
  fi
  printf '   pending: %s\n' "${pending[*]}"
  sleep 10
done
