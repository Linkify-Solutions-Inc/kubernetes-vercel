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

ts() { date '+%Y-%m-%d %H:%M:%S'; }

echo "================================================"
echo " FULL TEARDOWN — every experiment resource goes"
echo "  started $(ts)"
echo "================================================"

echo ">> $(ts) [1/6] stop GitOps reconciliation (ArgoCD must not fight the destroy)"
if kubectl get application -n argocd >/dev/null 2>&1; then
  kubectl delete -f gitops/bootstrap/app-of-apps.yaml >/dev/null 2>&1 || true
  helm uninstall argocd -n argocd >/dev/null 2>&1 || true
  kubectl delete ns argocd --ignore-not-found >/dev/null 2>&1 || true
fi

echo ">> $(ts) [2/6] delete every non-system namespace (catches experiment leftovers)"
# Capture the list to a file first: under `set -o pipefail` a pipeline that
# selects nothing (grep exit 1) would kill the whole script.
kubectl get ns -o jsonpath='{.items[*].metadata.name}' 2>/dev/null \
  | tr ' ' '\n' \
  | grep -vE '^(kube-system|kube-public|kube-node-lease|default)$' \
  > /tmp/minipaas-teardown-ns.txt || true

while read -r ns; do
  [ -z "$ns" ] && continue
  echo "    - deleting namespace: $ns ($(ts))"

  # Clear resource finalizers that can block namespace deletion — the ALB
  # controller's group finalizer on Ingress is the classic one. Without
  # this, `kubectl delete ns` hangs in Terminating forever.
  kubectl -n "$ns" get ingress -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
    | while read -r ing; do
        [ -n "$ing" ] && kubectl patch ingress "$ing" -n "$ns" \
          --type merge -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1 || true
      done
  kubectl -n "$ns" get svc -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
    | while read -r svc; do
        [ -n "$svc" ] && kubectl patch svc "$svc" -n "$ns" \
          --type merge -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1 || true
      done

  # Bound the wait so a stuck namespace can't hang the whole teardown.
  kubectl delete ns "$ns" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true

  # If it's still Terminating after the timeout, force-clear its finalizers.
  kubectl patch ns "$ns" --type merge -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1 || true
done < /tmp/minipaas-teardown-ns.txt
rm -f /tmp/minipaas-teardown-ns.txt

echo ">> $(ts) [3/6] destroy infrastructure via Terraform (the bill killer)"
cd "$(dirname "$0")/../infra"
# Stream the FULL destroy output live so you can see it progressing
# (EKS destroy takes ~15-25 min). `tee` logs a copy for later inspection;
# `|| true` lets the residual sweep in [4/6] catch anything left behind.
terraform destroy -auto-approve -no-color 2>&1 \
  | tee /tmp/minipaas-terraform-destroy.log || true

echo ">> $(ts) [4/6] residual sweep — things experiments could have created outside Terraform"
REGION="${AWS_REGION:-us-east-1}"

echo "    EC2 instances (all):"
aws ec2 describe-instances --region "$REGION" --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null \
  | tr '\t' '\n' | grep -v '^$' \
  | while read -r id; do echo "      - $(ts) terminating $id"; aws ec2 terminate-instances --region "$REGION" --instance-ids "$id" >/dev/null 2>&1 || true; done

echo "    EBS volumes (available / unattached):"
aws ec2 describe-volumes --region "$REGION" --filters Name=status,Values=available --query 'Volumes[].VolumeId' --output text 2>/dev/null \
  | tr '\t' '\n' | grep -v '^$' \
  | while read -r vol; do echo "      - $(ts) deleting $vol"; aws ec2 delete-volume --region "$REGION" --volume-id "$vol" >/dev/null 2>&1 || true; done

echo "    Elastic IPs (unassociated):"
aws ec2 describe-addresses --region "$REGION" --filters Name=association-id,Values='' --query 'Addresses[].AllocationId' --output text 2>/dev/null \
  | tr '\t' '\n' | grep -v '^$' \
  | while read -r eip; do echo "      - $(ts) releasing $eip"; aws ec2 release-address --region "$REGION" --allocation-id "$eip" >/dev/null 2>&1 || true; done

echo "    Load balancers (ALB/NLB):"
aws elbv2 describe-load-balancers --region "$REGION" --query 'LoadBalancers[].LoadBalancerArn' --output text 2>/dev/null \
  | tr '\t' '\n' | grep -v '^$' \
  | while read -r lb; do echo "      - $(ts) deleting $lb"; aws elbv2 delete-load-balancer --region "$REGION" --load-balancer-arn "$lb" >/dev/null 2>&1 || true; done

echo "    ECR repositories:"
aws ecr describe-repositories --region "$REGION" --query 'repositories[].repositoryName' --output text 2>/dev/null \
  | tr '\t' '\n' | grep -v '^$' \
  | while read -r repo; do echo "      - $(ts) deleting $repo"; aws ecr delete-repository --region "$REGION" --repository-name "$repo" --force >/dev/null 2>&1 || true; done

echo "    SQS queues:"
aws sqs list-queues --region "$REGION" --output text 2>/dev/null \
  | tr '\t' '\n' | grep -v '^$' \
  | while read -r q; do echo "      - $(ts) deleting $q"; aws sqs delete-queue --queue-url "$q" >/dev/null 2>&1 || true; done

echo ">> $(ts) [5/6] remove the state backend (S3 + DynamoDB), read from backend.tfvars"
if [ -f backend.tfvars ]; then
  BUCKET=$(awk -F'"' '/^bucket/{print $2}' backend.tfvars)
  TABLE=$(awk -F'"' '/dynamodb_table/{print $2}' backend.tfvars)
  if [ -n "$BUCKET" ]; then
    aws s3 rb "s3://$BUCKET" --force >/dev/null 2>&1 && echo "    - $(ts) state bucket $BUCKET removed" || echo "    - $(ts) (state bucket already gone)"
  fi
  if [ -n "$TABLE" ]; then
    aws dynamodb delete-table --table-name "$TABLE" >/dev/null 2>&1 && echo "    - $(ts) lock table $TABLE removed" || echo "    - $(ts) (lock table already gone)"
  fi
fi

echo ">> $(ts) [6/6] done. The account should be back to ~\$0. Confirm in AWS Cost Explorer tomorrow."
echo "    NOT touched by design: IAM Identity Center / SSO permission sets (your login)."
