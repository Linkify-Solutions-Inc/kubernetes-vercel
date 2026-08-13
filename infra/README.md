# infra/ — Terraform foundation

All AWS infrastructure for the Mini-PaaS platform, as code. See `docs/PRD.md` §3.1 for the requirements this satisfies.

## What lives here

| File | Purpose |
|---|---|
| `versions.tf` | Provider versions + S3/DynamoDB backend (configured via `backend.tfvars`) |
| `providers.tf` | AWS, Helm, Kubernetes, kubectl providers (cluster auth via EKS token) |
| `main.tf` | VPC (single NAT) + EKS cluster (`terraform-aws-eks`, Karpenter enabled) + ALB controller |
| `karpenter.tf` | Karpenter controller (IRSA) + Helm release + NodePool + EC2NodeClass |
| `ecr.tf` | Five private ECR repos (immutable tags) |
| `oidc.tf` | GitHub Actions OIDC provider + deploy role (ECR push only, no static keys) |
| `irsa.tf` | ALB controller IRSA role + policy |
| `policies/alb-controller.json` | The standard AWSLoadBalancerController IAM policy |
| `values/karpenter-values.yaml.tpl` | Karpenter Helm values template |
| `manifests/*.tpl` | Karpenter NodePool / EC2NodeClass templates |
| `bootstrap-state.sh` | One-time S3 bucket + DynamoDB lock table creation |

## Order of operations

```bash
# 1. one-time state backend
./bootstrap-state.sh

# 2. init + plan + apply (review the plan!)
terraform init -backend-config=backend.tfvars
terraform plan -out=plan.tfplan
terraform apply plan.tfplan

# 3. point kubectl at the cluster
aws eks update-kubeconfig --region us-east-1 --name mini-paas
```

## Gotchas (things that will bite the first run)

- **Module versions (verified 2026-08-13).** `terraform-aws-eks` is pinned to `~> 21.0` and the AWS provider to `~> 6.0`. The v21 module renamed several arguments vs older guides you'll find online: `cluster_name` → `name`, `cluster_version` → `kubernetes_version`, `cluster_endpoint_public_access` → `endpoint_public_access`, `cluster_addons` → `addons`. Karpenter is now a sub-module (`eks/aws//modules/karpenter`), not `enable_karpenter = true`.
- **Thumbprint.** `github_actions_thumbprint` points at `token.actions.githubusercontent.com`. If OIDC auth ever starts failing, re-verify the thumbprint before touching anything else.
- **Karpenter queue.** `interruption_queue` in the Helm values comes from the `module.karpenter.queue_name` output. If the sub-module version moves, confirm that output name.
- **Karpenter discovery tags (v21).** Private subnets carry `karpenter.sh/discovery` = cluster name; the node security group matches `kubernetes.io/cluster/<name>: owned`. If Karpenter never provisions, check those selectors first.
- **Single NAT.** `single_nat_gateway = true` is a deliberate cost choice (REQ-3.10-3) — one AZ becomes a failure point. Fine for a 30-day exercise, wrong for production.
- **Bootstrap node group.** It exists only to get the cluster running and host the Karpenter controller; Karpenter provisions everything else. Do not scale it to the workload.
