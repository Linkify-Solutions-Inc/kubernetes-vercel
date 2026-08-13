# ---------------------------------------------------------------------------
# Karpenter (EKS module v21 pattern)
#   - eks/aws//modules/karpenter  → controller role, node IAM role, SQS queue
#   - helm chart                  → the controller, pinned to the bootstrap node
#   - kubectl_manifest            → NodePool + EC2NodeClass
# ---------------------------------------------------------------------------
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.0"

  cluster_name = module.eks.cluster_name

  # Controller identity via EKS Pod Identity (the v21 way).
  create_pod_identity_association = true

  # Node IAM role that Karpenter-provisioned nodes assume. Name must match the
  # EC2NodeClass `role` field (local.name).
  node_iam_role_use_name_prefix = false
  node_iam_role_name            = local.name
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = local.tags
}

# The Karpenter chart lives on ECR Public (us-east-1) — needs a short-lived
# token, which is exactly what this data source provides.
data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}

resource "helm_release" "karpenter" {
  namespace           = "kube-system"
  name                = "karpenter"
  repository          = "oci://public.ecr.aws/karpenter"
  chart               = "karpenter"
  version             = var.karpenter_version
  wait                = false
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password

  values = [
    templatefile("${path.module}/values/karpenter-values.yaml.tpl", {
      cluster_name       = module.eks.cluster_name
      cluster_endpoint   = module.eks.cluster_endpoint
      interruption_queue = module.karpenter.queue_name
    })
  ]
}

resource "kubernetes_manifest" "karpenter_node_pool" {
  depends_on = [helm_release.karpenter]

  manifest = yamldecode(templatefile("${path.module}/manifests/karpenter-node-pool.yaml.tpl", {
    capacity_type  = var.karpenter_capacity_type
    instance_types = join(", ", formatlist("\"%s\"", var.karpenter_instance_types))
  }))
}

resource "kubernetes_manifest" "karpenter_ec2_node_class" {
  depends_on = [helm_release.karpenter]

  manifest = yamldecode(templatefile("${path.module}/manifests/karpenter-ec2nodeclass.yaml.tpl", {
    cluster_name = local.name
    node_role    = module.karpenter.node_iam_role_name
  }))
}
