#!/usr/bin/env bash
# DEMO: drift detection + self-healing.
#
# Git says hello-dev runs 1 replica. We "break" the cluster by hand in two ways
# and watch Argo CD put it back the way Git describes it.
source "$(dirname "$0")/lib.sh"

APP=hello-dev
TARGET_NS=hello-dev

bold "1) Manual drift: scale the Deployment to 5 replicas behind Git's back"
kubectl -n "$TARGET_NS" scale deploy/hello --replicas=5
sleep 2
info "Argo CD status right after the change: $(app_status $APP)"
info "Waiting for self-heal..."
for _ in $(seq 1 30); do
  r=$(kubectl -n "$TARGET_NS" get deploy hello -o jsonpath='{.spec.replicas}')
  [[ "$r" == "1" ]] && break
  sleep 2
done
ok "Replicas back to $(kubectl -n "$TARGET_NS" get deploy hello -o jsonpath='{.spec.replicas}') (as declared in Git)."

echo
bold "2) Disaster: delete the Deployment entirely"
kubectl -n "$TARGET_NS" delete deploy/hello --wait=false
info "Waiting for Argo CD to recreate it..."
for _ in $(seq 1 30); do
  kubectl -n "$TARGET_NS" get deploy hello >/dev/null 2>&1 && break
  sleep 2
done
kubectl -n "$TARGET_NS" rollout status deploy/hello --timeout=120s
ok "Deployment recreated from Git. App status: $(app_status $APP)"

echo
info "Inspect the history in the UI: $ARGOCD_URL/applications/argocd/$APP"
