#!/usr/bin/env bash
# Give the read-only local user "viewer" (declared in bootstrap/argocd-values.yaml)
# a password, WITHOUT committing a password hash to Git.
#
# We borrow the `argocd` binary that already ships inside the argocd-server pod
# to compute the bcrypt hash, then store it in the argocd-secret Secret.
source "$(dirname "$0")/lib.sh"

PASSWORD=${VIEWER_PASSWORD:-viewer123}

info "Hashing password with the argocd binary inside the server pod..."
hash=$(kubectl -n "$NS" exec deploy/argocd-server -- argocd account bcrypt --password "$PASSWORD")

kubectl -n "$NS" patch secret argocd-secret --type merge -p "{
  \"stringData\": {
    \"accounts.viewer.password\": \"$hash\",
    \"accounts.viewer.passwordMtime\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
  }
}" >/dev/null
ok "User 'viewer' can now log in at $ARGOCD_URL with password '$PASSWORD' (read-only)."
