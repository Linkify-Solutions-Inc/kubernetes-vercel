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
REGION="${AWS_REGION:-us-east-1}"

# Discovery-based, like the streaming project: find the VPC by its tags via the
# AWS API — NOT via `terraform output`, which also needs the state lock and so
# fails exactly when a stale lock from an interrupted run is present (the
# chicken-and-egg that skipped the SG pre-clean on 2026-08-13).
find_vpc() {
  local v
  v=$(aws ec2 describe-vpcs --region "$REGION" \
    --filters "Name=tag:Name,Values=mini-paas" "Name=tag:Project,Values=mini-paas" \
    --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)
  [ "$v" = "None" ] && v=""
  echo "$v"
}

echo "================================================"
echo " FULL TEARDOWN — every experiment resource goes"
echo "  started $(ts)"
echo "================================================"

echo ">> $(ts) [1/7] stop GitOps reconciliation (ArgoCD must not fight the destroy)"
if kubectl get application -n argocd >/dev/null 2>&1; then
  # Disarm selfHeal on every Application first, or ArgoCD resurrects each
  # resource the instant we delete it (the streaming project's A1 ordering rule).
  kubectl -n argocd patch application --all --type merge \
    -p '{"spec":{"syncPolicy":{"automated":null}}}' >/dev/null 2>&1 || true
  kubectl delete -f gitops/bootstrap/app-of-apps.yaml >/dev/null 2>&1 || true
  helm uninstall argocd -n argocd >/dev/null 2>&1 || true
  kubectl delete ns argocd --ignore-not-found >/dev/null 2>&1 || true
fi

echo ">> $(ts) [2/7] delete every non-system namespace (catches experiment leftovers)"
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

echo ">> $(ts) [3/7] pre-clean destroy blockers, then destroy infrastructure via Terraform"
cd "$(dirname "$0")/../infra"
# Pre-clean, BEFORE the destroy: the ALB controller and Karpenter create
# resources terraform cannot see (the ALB "Shared Backend" SG, Karpenter-
# orphaned EC2 instances). Left alone they block the destroy's last step —
# VPC deletion — and force a slow second pass. Remove them up front so one
# destroy pass completes. Plain for-loops, not grep|while pipelines: under
# `set -o pipefail` a grep that selects nothing would kill the script.
VPC_ID=$(find_vpc)
if [ -n "$VPC_ID" ]; then
  echo "    - $(ts) terminating stray instances in the VPC (Karpenter-orphaned nodes block SG deletion)"
  IDS=$(aws ec2 describe-instances --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null || true)
  for id in $IDS; do
    echo "      - $(ts) terminating $id"
    aws ec2 terminate-instances --region "$REGION" --instance-ids "$id" >/dev/null 2>&1 || true
  done
  echo "    - $(ts) deleting non-default SGs in the VPC (e.g. the ALB controller's shared SG)"
  SGS=$(aws ec2 describe-security-groups --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null || true)
  for sg in $SGS; do
    echo "      - $(ts) deleting SG $sg"
    aws ec2 delete-security-group --region "$REGION" --group-id "$sg" >/dev/null 2>&1 || true
  done
fi
echo "    - $(ts) destroying via Terraform. If the last step shows 'Still destroying... [id=vpc...]'"
echo "      for a few minutes, AWS is retrying DeleteVpc — do NOT Ctrl-C. If it fails, the"
echo "      sweep below removes any remaining SG/ENI blocker and retries automatically."
# Stream the FULL destroy output live so you can see it progressing (EKS
# destroy takes ~15-25 min). A Ctrl-C mid-destroy leaves the state lock held;
# detect that, force-unlock, and retry once. DESTROY_OK gates phase 5.
DESTROY_OK=0
run_destroy() {
  if terraform destroy -auto-approve -no-color 2>&1 | tee /tmp/minipaas-terraform-destroy.log; then
    DESTROY_OK=1
    return
  fi
  # Stale lock from a Ctrl-C mid-destroy? Force-unlock and retry once.
  # `|| true`: under `set -o pipefail`, grep finding nothing (e.g. a checksum
  # error rather than a lock error) returns 1 and would kill the script here —
  # exactly the abort seen on 2026-08-13.
  LOCK_ID=$(grep -oE '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' \
    /tmp/minipaas-terraform-destroy.log 2>/dev/null | head -1) || true
  if [ -n "$LOCK_ID" ]; then
    echo "    - $(ts) stale state lock ($LOCK_ID) from an interrupted run — force-unlocking and retrying"
    terraform force-unlock -force "$LOCK_ID" >/dev/null 2>&1 || true
    if terraform destroy -auto-approve -no-color 2>&1 | tee /tmp/minipaas-terraform-destroy.log; then
      DESTROY_OK=1
      return
    fi
  fi
  # State backend corrupted (torn write: S3 checksum != DynamoDB Digest)?
  # Terraform will not touch it. The pre-clean has already removed every SG/ENI
  # blocker, so the VPC is hollow and can be deleted via the AWS CLI; phase 5
  # then drops the backend. Only claim success if the VPC really went away, or
  # phase 5 would orphan a live VPC.
  if grep -qE "checksum|expected content" /tmp/minipaas-terraform-destroy.log 2>/dev/null; then
    echo "    - $(ts) state backend corrupted (checksum mismatch from an interrupted write) — removing the VPC via AWS CLI"
    V=$(find_vpc)
    if [ -z "$V" ]; then
      echo "      - $(ts) VPC already gone"
      DESTROY_OK=1
    elif aws ec2 delete-vpc --region "$REGION" --vpc-id "$V" >/dev/null 2>&1; then
      echo "      - $(ts) deleted VPC $V via AWS CLI"
      n=0
      while [ $n -lt 12 ] && [ -n "$(aws ec2 describe-vpcs --region "$REGION" --vpc-ids "$V" --query 'Vpcs[0].VpcId' --output text 2>/dev/null)" ]; do
        sleep 5; n=$((n+1))
      done
      DESTROY_OK=1
    else
      echo "      - $(ts) VPC $V still has dependencies — NOT marking complete; inspect and re-run"
    fi
  fi
  # Last resort: terraform may be unable to proceed at all (corrupted state,
  # deleted lock table, any backend error). If the two billable resources
  # terraform owned — the VPC and the EKS cluster — are both gone from AWS, the
  # destroy is effectively complete even though terraform errors; phase 5 then
  # drops the broken backend. (VPC gone implies its subnets/IGW/NAT are gone
  # too — they cannot outlive the VPC. The phase-4 sweep cleans non-terraform
  # leftovers like ECR/ALB/instances before phase 5 runs.)
  if [ "$DESTROY_OK" != "1" ]; then
    V=$(find_vpc)
    CLUSTERS=$(aws eks list-clusters --region "$REGION" --query 'clusters' --output text 2>/dev/null || true)
    if [ -z "$V" ] && [ -z "$CLUSTERS" ]; then
      echo "    - $(ts) VPC and EKS cluster are both gone — treating the destroy as complete despite the backend error"
      DESTROY_OK=1
    fi
  fi
}
run_destroy

echo ">> $(ts) [4/7] residual sweep — things experiments could have created outside Terraform"

# Each sweep block ends with `|| true`: under `set -o pipefail` a `grep -v` that
# selects nothing (a fully clean account) exits 1 and would kill the whole
# script before phase 5 could remove the state backend.
echo "    EC2 instances (all):"
aws ec2 describe-instances --region "$REGION" --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null \
  | tr '\t' '\n' | grep -v '^$' \
  | while read -r id; do echo "      - $(ts) terminating $id"; aws ec2 terminate-instances --region "$REGION" --instance-ids "$id" >/dev/null 2>&1 || true; done || true

echo "    EBS volumes (available / unattached):"
aws ec2 describe-volumes --region "$REGION" --filters Name=status,Values=available --query 'Volumes[].VolumeId' --output text 2>/dev/null \
  | tr '\t' '\n' | grep -v '^$' \
  | while read -r vol; do echo "      - $(ts) deleting $vol"; aws ec2 delete-volume --region "$REGION" --volume-id "$vol" >/dev/null 2>&1 || true; done || true

echo "    Elastic IPs (unassociated):"
aws ec2 describe-addresses --region "$REGION" --filters Name=association-id,Values='' --query 'Addresses[].AllocationId' --output text 2>/dev/null \
  | tr '\t' '\n' | grep -v '^$' \
  | while read -r eip; do echo "      - $(ts) releasing $eip"; aws ec2 release-address --region "$REGION" --allocation-id "$eip" >/dev/null 2>&1 || true; done || true

echo "    Load balancers (ALB/NLB):"
aws elbv2 describe-load-balancers --region "$REGION" --query 'LoadBalancers[].LoadBalancerArn' --output text 2>/dev/null \
  | tr '\t' '\n' | grep -v '^$' \
  | while read -r lb; do echo "      - $(ts) deleting $lb"; aws elbv2 delete-load-balancer --region "$REGION" --load-balancer-arn "$lb" >/dev/null 2>&1 || true; done || true

echo "    ECR repositories:"
aws ecr describe-repositories --region "$REGION" --query 'repositories[].repositoryName' --output text 2>/dev/null \
  | tr '\t' '\n' | grep -v '^$' \
  | while read -r repo; do echo "      - $(ts) deleting $repo"; aws ecr delete-repository --region "$REGION" --repository-name "$repo" --force >/dev/null 2>&1 || true; done || true

echo "    SQS queues:"
aws sqs list-queues --region "$REGION" --output text 2>/dev/null \
  | tr '\t' '\n' | grep -vE '^($|None)$' \
  | while read -r q; do echo "      - $(ts) deleting $q"; aws sqs delete-queue --queue-url "$q" >/dev/null 2>&1 || true; done || true

echo "    Security groups (non-default, leftover in the VPC — e.g. the ALB controller's shared SG):"
# Plain for-loop, not a grep|while pipeline: under `set -o pipefail` a grep that
# selects nothing would kill the whole script (the phase-2 landmine).
VPC_ID=$(find_vpc)
if [ -n "$VPC_ID" ]; then
  SGS=$(aws ec2 describe-security-groups --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null || true)
  for sg in $SGS; do
    echo "      - $(ts) deleting SG $sg"
    aws ec2 delete-security-group --region "$REGION" --group-id "$sg" >/dev/null 2>&1 || true
  done
fi

# If the destroy failed, the sweep above removed the blockers (leftover ENIs,
# SGs) — retry once so the VPC can finish tearing down.
if [ "$DESTROY_OK" != "1" ]; then
  echo "    - $(ts) destroy did not complete earlier — retrying now that leftover SG/ENI blockers are gone"
  run_destroy
fi

echo ">> $(ts) [5/7] remove the state backend (S3 + DynamoDB), read from backend.tfvars"
# Only remove the state if the destroy actually completed — otherwise the
# EKS cluster/VPC/IAM stay orphaned and billable with no state to destroy them.
if [ "$DESTROY_OK" != "1" ]; then
  echo "    - $(ts) terraform destroy did NOT complete — KEEPING the state backend so a re-run can finish the destroy."
elif [ -f backend.tfvars ]; then
  BUCKET=$(awk -F'"' '/^bucket/{print $2}' backend.tfvars)
  TABLE=$(awk -F'"' '/dynamodb_table/{print $2}' backend.tfvars)
  if [ -n "$BUCKET" ]; then
    # The state bucket has versioning ENABLED — `aws s3 rb --force` cannot
    # remove versioned objects (BucketNotEmpty), and each failed destroy wrote
    # another state version. Delete every version + delete marker first
    # (paginated), then the bucket itself.
    if aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
      echo "      - $(ts) clearing object versions from $BUCKET"
      python3 - "$BUCKET" <<'PYEOF' 2>/dev/null || true
import json, subprocess, sys
b = sys.argv[1]
def run(*a): return subprocess.run(a, capture_output=True, text=True, check=True)
objs = []
km = vm = ""
while True:
    cmd = ["aws","s3api","list-object-versions","--bucket",b,"--output","json"]
    if km: cmd += ["--key-marker",km,"--version-id-marker",vm]
    d = json.loads(run(*cmd).stdout)
    objs += [{"Key":v["Key"],"VersionId":v["VersionId"]} for v in d.get("Versions",[])]
    objs += [{"Key":m["Key"],"VersionId":m["VersionId"]} for m in d.get("DeleteMarkers",[])]
    if not d.get("IsTruncated"): break
    km, vm = d.get("NextKeyMarker",""), d.get("NextVersionIdMarker","")
for i in range(0, len(objs), 1000):
    run("aws","s3api","delete-objects","--bucket",b,"--delete",
        json.dumps({"Objects":objs[i:i+1000],"Quiet":True}))
print(f"deleted {len(objs)} versions")
PYEOF
      if aws s3 rb "s3://$BUCKET" --force >/dev/null 2>&1; then
        echo "    - $(ts) state bucket $BUCKET removed"
      else
        echo "    - $(ts) state bucket $BUCKET STILL PRESENT — re-run the teardown to retry"
      fi
    else
      echo "    - $(ts) (state bucket already gone)"
    fi
  fi
  if [ -n "$TABLE" ]; then
    # delete-table returns as soon as the table enters DELETING — wait for it
    # to be fully gone so the phase-6 audit reports a clean account.
    if aws dynamodb describe-table --table-name "$TABLE" >/dev/null 2>&1; then
      aws dynamodb delete-table --table-name "$TABLE" >/dev/null 2>&1 || true
      aws dynamodb wait table-not-exists --table-name "$TABLE" >/dev/null 2>&1 \
        && echo "    - $(ts) lock table $TABLE removed" \
        || echo "    - $(ts) lock table $TABLE still deleting — will clear shortly"
    else
      echo "    - $(ts) (lock table already gone)"
    fi
  fi
fi

echo ">> $(ts) [6/7] zero-cost audit — every resource line below should be EMPTY"
# Final proof of cleanup (ported from the streaming project's [9/9]): print
# each billable resource type; anything still present shows up here, so "the
# account is clean" is verified, not assumed.
LEFTOVERS=0
audit(){ # audit <label> <aws cmd args...>
  local label="$1"; shift
  local out
  out=$("$@" 2>/dev/null | tr '\n' ' ' || true)
  if [ -n "$out" ]; then LEFTOVERS=$((LEFTOVERS+1)); fi
  printf '    %-18s %s\n' "$label:" "${out:-<empty>}"
}
audit "EC2 instances"     aws ec2 describe-instances --region "$REGION" --filters Name=instance-state-name,Values=running,pending,stopping,stopped --query 'Reservations[].Instances[].InstanceId' --output text
audit "EBS volumes"       aws ec2 describe-volumes --region "$REGION" --query 'Volumes[].VolumeId' --output text
audit "Elastic IPs"       aws ec2 describe-addresses --region "$REGION" --query 'Addresses[].AllocationId' --output text
audit "Load balancers"    aws elbv2 describe-load-balancers --region "$REGION" --query 'LoadBalancers[].LoadBalancerName' --output text
audit "VPCs (non-default)" aws ec2 describe-vpcs --region "$REGION" --query 'Vpcs[?IsDefault==`false`].VpcId' --output text
audit "NAT gateways"      aws ec2 describe-nat-gateways --region "$REGION" --filter Name=state,Values=available,pending --query 'NatGateways[].NatGatewayId' --output text
audit "EKS clusters"      aws eks list-clusters --region "$REGION" --query 'clusters' --output text
audit "ECR repos"         aws ecr describe-repositories --region "$REGION" --query 'repositories[].repositoryName' --output text
audit "S3 buckets"        aws s3api list-buckets --query 'Buckets[].Name' --output text
audit "DynamoDB tables"   aws dynamodb list-tables --region "$REGION" --query 'TableNames' --output text
if [ "$LEFTOVERS" -gt 0 ]; then
  echo "    !! $(ts) $LEFTOVERS resource type(s) still show leftovers above — investigate before declaring done."
else
  echo "    ✓ $(ts) clean — no billable resources remain."
fi

echo ">> $(ts) [7/7] done. The account should be back to ~\$0. Confirm in AWS Cost Explorer tomorrow."
echo "    NOT touched by design: IAM Identity Center / SSO permission sets (your login)."
