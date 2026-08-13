# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]

  # Single NAT gateway keeps the exercise under the cost ceiling. The ALB lives in
  # public subnets; EKS worker nodes run in private subnets and egress via NAT.
  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false
  enable_vpn_gateway     = false
  enable_flow_log        = false

  # Karpenter auto-discovery (v21 convention: key = karpenter.sh/discovery,
  # value = cluster name).
  private_subnet_tags = {
    "karpenter.sh/discovery" = local.name
  }

  tags = local.tags
}

# ---------------------------------------------------------------------------
# EKS cluster
# ---------------------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name                   = local.name
  kubernetes_version     = var.cluster_version
  endpoint_public_access = true

  # Whoever runs `terraform apply` becomes a cluster admin (kubectl access).
  # This is what gives both operators access to the cluster.
  enable_cluster_creator_admin_permissions = true # kubectl from your laptop

  # No customer-managed KMS key: EKS still encrypts etcd with its own
  # AWS-managed key. Keeps the IAM surface small enough for Fatima's
  # StreamingDeploy permission set AND keeps teardown truly zero-cost
  # (KMS keys linger 7 days and cost $1/mo).
  # encryption_config = null skips the module's KMS wiring (its default {} would
  # demand a key_arn once create_kms_key is false).
  create_kms_key   = false
  encryption_config = null

  # before_compute on the addons a node needs to become READY (coredns, kube-proxy,
  # vpc-cni). If they default to after-compute, EKS holds the node group in CREATING
  # because the node cannot go Ready without the CNI — a real deadlock we hit live
  # on 2026-08-13. ebs-csi-driver is fine after compute.
  addons = {
    coredns = {
      before_compute = true
    }
    kube-proxy = {
      before_compute = true
    }
    vpc-cni = {
      before_compute = true
    }
    aws-ebs-csi-driver = {}
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_irsa = true

  # Karpenter controller + node role + interruption queue are provisioned by the
  # Karpenter sub-module in karpenter.tf (eks/aws//modules/karpenter).

  # Bootstrap node group only — Karpenter provisions everything after this. It
  # also carries the controller label so the Karpenter pod runs on a node
  # Karpenter does not manage.
  eks_managed_node_groups = {
    bootstrap = {
      desired_size   = var.node_desired_size
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      instance_types = [var.node_instance_type]

      labels = {
        role                      = "bootstrap"
        "karpenter.sh/controller" = "true"
      }

      tags = merge(local.tags, {
        "karpenter.sh/discovery" = local.name
      })
    }
  }

  tags = local.tags
}

# ---------------------------------------------------------------------------
# AWS Load Balancer Controller (infrastructure — not a tenant workload)
# ---------------------------------------------------------------------------
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.10.1"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }
  set {
    name  = "region"
    value = var.region
  }
  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }
  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.alb_controller.arn
  }
  set {
    name  = "replicaCount"
    value = "1"
  }
}
