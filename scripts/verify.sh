#!/usr/bin/env bash
# Post-build verification on AWS — the Appendix D checkpoints as a script.
# Run from the repository root while the platform is up.
#
#   ./scripts/verify.sh
set -uo pipefail

FAIL=0

check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "  [PASS] $desc"
  else
    echo "  [FAIL] $desc"
    FAIL=1
  fi
}

echo "== Appendix D verification =="

echo "-- cluster --"
check "nodes Ready"                kubectl get nodes --no-headers
check "kube-system healthy"        kubectl get pods -n kube-system --field-selector=status.phase=Running
check "tenant namespaces present"  kubectl get ns app-api-node >/dev/null 2>&1

echo "-- gitops / catalog --"
check "ArgoCD apps present"        bash -c 'kubectl get applications -n argocd --no-headers | grep -c api-node >/dev/null'
for app in api-node web-node worker-node py-api go-api; do
  check "tenant ${app} namespace"  kubectl get ns "app-${app}" >/dev/null 2>&1
  check "${app} deployment ready"  kubectl -n "app-${app}" rollout status deploy/"${app}" --timeout=60s
done

echo "-- isolation --"
check "quota present"              bash -c 'kubectl -n app-api-node get resourcequota quota >/dev/null 2>&1'
check "limitrange present"         bash -c 'kubectl -n app-api-node get limitrange limits >/dev/null 2>&1'
check "networkpolicy present"      bash -c 'kubectl -n app-api-node get networkpolicy default-deny >/dev/null 2>&1'

echo "-- autoscaling --"
check "HPA present for api-node"   bash -c 'kubectl -n app-api-node get hpa api-node >/dev/null 2>&1'
check "Karpenter installed"        bash -c 'kubectl -n kube-system get pod -l app.kubernetes.io/name=karpenter --no-headers | grep -c Running >/dev/null'

echo "-- observability --"
check "monitoring ns present"      kubectl get ns monitoring >/dev/null 2>&1
check "prometheus running"         bash -c 'kubectl -n monitoring get pod -l app.kubernetes.io/name=prometheus --no-headers | grep -c Running >/dev/null'
check "grafana running"            bash -c 'kubectl -n monitoring get pod -l app.kubernetes.io/name=grafana --no-headers | grep -c Running >/dev/null'

if [ "$FAIL" -eq 0 ]; then
  echo "ALL CHECKS PASSED — the platform is up and healthy."
else
  echo "SOME CHECKS FAILED — inspect the [FAIL] lines; see docs/TM-001 App. A."
  exit 1
fi
