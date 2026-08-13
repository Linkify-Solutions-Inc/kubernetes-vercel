#!/usr/bin/env bash
# FULL TEARDOWN.
# This org has no production projects — this script is allowed to remove
# everything the experiments could have created, and it does: GitOps, every
# non-system namespace, the whole Terraform stack, AND a residual sweep of the
# account. Run from the repository root.
#
#   AWS_PROFILE=streaming-admin ./scripts/teardown.sh
#
# NOT touched by design: IAM Identity Center / SSO permission sets and the
# reserved SSO roles — that is how everyone logs in.
set -euo pipefail

export AWS_PROFILE="${AWS_PROFILE:-streaming-admin}"

echo "================================================"
echo " FULL TEARDOWN — every experiment resource goes"
echo "================================================"

echo ">> [1/6] stop GitOps reconciliation (ArgoCD must not fight the destroy)"
if kubectl get application -n argocd >/dev/null 2>&1; then
  kubectl delete -f gitops/bootstrap/app-of-apps.yaml >/dev/null 2>&1 || true
  helm uninstall argocd -n argocd >/dev/null 2>&1 || true
  kubectl delete ns argocd --ignore-not-found >/dev/null 2>&1 || true
fi

echo ">> [2/6] delete every non-system namespace (catches experiment leftovers)"
kubectl get ns -o jsonpath='{.items[*].metadata.name}' 2>/dev/null \
  | tr ' ' '\n' \
  | grep -vE '^(kube-system|kube-public|kube-node-lease|default)$' \
  | while read -r ns; do
      [ -z "$ns" ] && continue
      echo "    - deleting namespace: $ns"
      kubectl delete ns "$ns" --ignore-not-found >/dev/null 2>&1 || true
    done

echo ">> [3/6] destroy infrastructure via Terraform (the bill killer)"
cd "$(dirname "$0")/../infra"
terraform destroy -auto-approve

echo ">> [4/6] residual sweep — things experiments could have created outside Terraform"
REGION="${AWS_REGION:-us-east-1}"

echo "    EC2 instances (all):"
aws ec2 describe-instances --region "$REGION" --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null \
  | tr '\t' '\n' | grep -v '^$' \
  | while read -r id; do echo "      - terminating $id"; aws ec2 terminate-instances --region "$REGION" --instance-ids "$id" >/dev/null 2>&1 || true; done

echo "    EBS volumes (available / unattached):"
aws ec2 describe-volumes --region "$REGION" --filters Name=status,Values=available --query 'Volumes[].VolumeId' --output text 2>/dev/null \
  | tr '\t' '\n' | grep -v '^$' \
  | while read -r vol; do echo "      - deleting $vol"; aws ec2 delete-volume --region "$REGION" --volume-id "$vol" >/dev/null 2>&1 || true; done

echo "    Elastic IPs (unassociated):"
aws ec2 describe-addresses --region "$REGION" --filters Name=association-id,Values='' --query 'Addresses[].AllocationId' --output text 2>/dev/null \
  | tr '\t' '\n' | grep -v '^$' \
  | while read -r eip; do echo "      - releasing $eip"; aws ec2 release-address --region "$REGION" --allocation-id "$eip" >/dev/null 2>&1 || true; done

echo "    Load balancers (ALB/NLB):"
aws elbv2 describe-load-balancers --region "$REGION" --query 'LoadBalancers[].LoadBalancerArn' --output text 2>/dev/null \
  | tr '\t' '\n' | grep -v '^$' \
  | while read -r lb; do echo "      - deleting $lb"; aws elbv2 delete-load-balancer --region "$REGION" --load-balancer-arn "$lb" >/dev/null 2>&1 || true; done

echo "    ECR repositories:"
aws ecr describe-repositories --region "$REGION" --query 'repositories[].repositoryName' --output text 2>/dev/null \
  | tr '\t' '\n' | grep -v '^$' \
  | while read -r repo; do echo "      - deleting $repo"; aws ecr delete-repository --region "$REGION" --repository-name "$repo" --force >/dev/null 2>&1 || true; done

echo "    SQS queues:"
aws sqs list-queues --region "$REGION" --output text 2>/dev/null \
  | tr '\t' '\n' | grep -v '^$' \
  | while read -r q; do echo "      - deleting $q"; aws sqs delete-queue --queue-url "$q" >/dev/null 2>&1 || true; done

echo ">> [5/6] remove the state backend (S3 + DynamoDB), read from backend.tfvars"
if [ -f backend.tfvars ]; then
  BUCKET=$(awk -F'"' '/^bucket/{print $2}' backend.tfvars)
  TABLE=$(awk -F'"' '/dynamodb_table/{print $2}' backend.tfvars)
  if [ -n "$BUCKET" ]; then
    aws s3 rb "s3://$BUCKET" --force >/dev/null 2>&1 && echo "    - state bucket $BUCKET removed" || echo "    - (state bucket already gone)"
  fi
  if [ -n "$TABLE" ]; then
    aws dynamodb delete-table --table-name "$TABLE" >/dev/null 2>&1 && echo "    - lock table $TABLE removed" || echo "    - (lock table already gone)"
  fi
fi

echo ">> [6/6] done. The account should be back to ~\$0. Confirm in AWS Cost Explorer tomorrow."
echo "    NOT touched by design: IAM Identity Center / SSO permission sets (your login)."
