#!/usr/bin/env bash
# DEMO: RBAC. The "viewer" user (role:readonly) can SEE applications but
# is NOT allowed to SYNC them. Uses the Argo CD REST API directly.
source "$(dirname "$0")/lib.sh"

PASSWORD=${VIEWER_PASSWORD:-viewer123}

bold "Logging in as 'viewer'..."
token=$(api_token viewer "$PASSWORD") || fail "Login failed. Did you run 'make viewer'?"
[[ -n "$token" && "$token" != "null" ]] || fail "Login failed. Did you run 'make viewer'?"
ok "Logged in."

bold "1) viewer lists applications (allowed by role:readonly)"
curl -sf "$ARGOCD_URL/api/v1/applications" -H "Authorization: Bearer $token" \
  | jq -r '.items[].metadata.name' | sed 's/^/   - /'

bold "2) viewer tries to SYNC hello-prod (should be denied)"
code=$(curl -s -o /tmp/argocd-rbac-demo.json -w '%{http_code}' -X POST \
  "$ARGOCD_URL/api/v1/applications/hello-prod/sync" \
  -H "Authorization: Bearer $token" -H 'Content-Type: application/json' -d '{}')
msg=$(jq -r '.message // empty' /tmp/argocd-rbac-demo.json 2>/dev/null || true)
rm -f /tmp/argocd-rbac-demo.json
if [[ "$code" == "403" ]]; then
  ok "Denied with HTTP 403: $msg"
else
  fail "Expected HTTP 403, got $code: $msg"
fi
