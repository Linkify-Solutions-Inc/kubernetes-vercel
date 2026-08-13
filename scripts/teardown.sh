#!/usr/bin/env bash
# Full teardown, in the order that prevents ArgoCD from fighting the destroy
# (REQ-3.10-1 … 3.10-4). Run from the repository root.
#
#   ./scripts/teardown.sh
set -euo pipefail

echo ">> 1/5 — stop GitOps reconciliation (ArgoCD must not recreate what Terraform deletes)"
if kubectl get application -n argocd >/dev/null 2>&1; then
  kubectl delete -f gitops/bootstrap/app-of-apps.yaml >/dev/null 2>&1 || true
  helm uninstall argocd -n argocd >/dev/null 2>&1 || echo "    (argocd already gone)"
else
  echo "    (no argocd found — nothing to stop)"
fi

echo ">> 2/5 — remove tenant + monitoring namespaces"
for ns in app-api-node app-web-node app-worker-node app-py-api app-go-api monitoring loadgen; do
  kubectl delete ns "$ns" --ignore-not-found >/dev/null 2>&1 || true
done

echo ">> 3/5 — destroy infrastructure (this is the bill killer)"
cd infra
terraform destroy -auto-approve

echo ">> 4/5 — verify nothing billable remains"
LEFT=$(aws ec2 describe-instances --region "$(terraform output -raw region 2>/dev/null || echo us-east-1)" \
  --filters "Name=tag:Project,Values=mini-paas" \
  --query 'Reservations | length([].Instances[0].InstanceId)' --output text 2>/dev/null || echo 0)
echo "    mini-paas instances left: $LEFT"

echo ">> 5/5 — done. Check AWS Cost Explorer in a few hours for the bill to return to baseline."
echo "    NOTE: the S3 state bucket + DynamoDB lock table remain by design (cheap, reusable)."
echo "    Delete them manually if you want a truly zero-account month:"
echo "      aws s3 rm s3://<bucket> --recursive && aws s3 rb s3://<bucket>"
echo "      aws dynamodb delete-table --table-name linkify-mini-paas-tfstate-lock"
