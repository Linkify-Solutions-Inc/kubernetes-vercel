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

  # The ALB controller discovers public subnets by the kubernetes.io/role/elb
  # tag. Without it, the ALB is never created ("couldn't auto-discover subnets").
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
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

  # Explicit admin access entries for BOTH operators, instead of the auto
  # cluster_creator entry — the auto entry silently follows whoever runs apply
  # (created it as StreamingDeploy, then swapped to whoever runs it next).
  # Listing both keeps Fatima's StreamingDeploy access AND our AdminAccess.
  enable_cluster_creator_admin_permissions = false
  access_entries = {
    aayush-admin = {
      kubernetes_groups = []
      principal_arn     = "arn:aws:iam::242626138899:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdminAccess_8d36146d2e13acf4"
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
    fatima-deploy = {
      kubernetes_groups = []
      principal_arn     = "arn:aws:iam::242626138899:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_StreamingDeploy_c76ab22657ecbba5"
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  # ALB traffic to app ports (health checks + routing). Declared here so the
  # node SG always allows the ALB — the ALB controller's per-service SG rule
  # bookkeeping can miss ports (hit live on 2026-08-13: only 8081 was added).
  node_security_group_additional_rules = {
    ingress_app_ports = {
      description = "ALB app-port ingress (api,py,go 3000; web 8080; worker 8081)"
      protocol    = "tcp"
      from_port   = 3000
      to_port     = 8081
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }

  # No customer-managed KMS key: EKS still encrypts etcd with its own
  # AWS-managed key. Keeps the IAM surface small enough for Fatima's
  # StreamingDeploy permission set AND keeps teardown truly zero-cost
  # (KMS keys linger 7 days and cost $1/mo).
  # encryption_config = null skips the module's KMS wiring (its default {} would
  # demand a key_arn once create_kms_key is false).
  create_kms_key    = false
  encryption_config = null

  # before_compute on the addons a node needs to become READY (coredns, kube-proxy,
  # vpc-cni): if they default to after-compute, EKS holds the node group in CREATING
  # because the node cannot go Ready without the CNI.
  # eks-pod-identity-agent is required: Karpenter authenticates via EKS Pod Identity,
  # and without this addon no credentials are injected into its pod.
  # No aws-ebs-csi-driver: the demo apps are stateless (no PVCs), and the addon's
  # controller crashes without a provisioned IRSA role for its service account.
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
    eks-pod-identity-agent = {
      before_compute = true
    }
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

  # wait = true: the controller registers a mutating webhook for Services; any
  # Service created before the pod is Ready fails with "no endpoints available".
  # Blocking here orders everything after it (karpenter's chart creates a Service).
  wait    = true
  timeout = 600

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
