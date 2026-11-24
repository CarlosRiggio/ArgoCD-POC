#!/usr/bin/env bash
# Small helpers shared by the scripts in this folder.
set -euo pipefail

NS=argocd
ARGOCD_URL=${ARGOCD_URL:-http://localhost:8080}

bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
info()  { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()    { printf '\033[32m✔\033[0m  %s\n' "$*"; }
warn()  { printf '\033[33m!\033[0m  %s\n' "$*"; }
fail()  { printf '\033[31m✘\033[0m  %s\n' "$*"; exit 1; }

# Print "<sync> <health>" for an Argo CD Application.
app_status() {
  kubectl -n "$NS" get application "$1" \
    -o jsonpath='{.status.sync.status} {.status.health.status}' 2>/dev/null || true
}

admin_password() {
  kubectl -n "$NS" get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' | base64 -d
}

# Log in to the Argo CD REST API and print a session token.
api_token() {
  local user=$1 pass=$2
  curl -sf "$ARGOCD_URL/api/v1/session" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"$user\",\"password\":\"$pass\"}" | jq -r .token
}
