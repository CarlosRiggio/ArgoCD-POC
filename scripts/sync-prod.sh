#!/usr/bin/env bash
# "Promote" to production: trigger a MANUAL sync of the prod applications.
#
# Equivalent to pressing SYNC in the UI, or to:
#     argocd app sync hello-prod podinfo-prod
# Here we do it with plain kubectl by setting the Application's `operation`
# field, which is exactly what the UI/CLI do under the hood.
source "$(dirname "$0")/lib.sh"

if [[ $# -gt 0 ]]; then APPS=("$@"); else APPS=(hello-prod podinfo-prod); fi

for app in "${APPS[@]}"; do
  info "Requesting sync of $app"
  kubectl -n "$NS" patch application "$app" --type merge -p '{
    "operation": {
      "initiatedBy": { "username": "make sync-prod" },
      "sync": { "prune": true, "syncStrategy": { "hook": {} } }
    }
  }' >/dev/null
done

for app in "${APPS[@]}"; do
  info "Waiting for $app to be Synced + Healthy..."
  for _ in $(seq 1 60); do
    read -r sync health <<<"$(app_status "$app")"
    phase=$(kubectl -n "$NS" get application "$app" -o jsonpath='{.status.operationState.phase}')
    if [[ "$sync" == "Synced" && "$health" == "Healthy" && "$phase" == "Succeeded" ]]; then
      ok "$app: Synced / Healthy"; continue 2
    fi
    sleep 5
  done
  fail "$app did not converge (sync=$sync health=$health phase=$phase)"
done
