provider "aws" {
  region = var.region
  default_tags {
    tags = local.tags
  }
}

# ECR Public is only served from us-east-1 (used for the Karpenter chart token).
provider "aws" {
  alias  = "virginia"
  region = "us-east-1"
}

# Cluster auth token for the helm / kubernetes / kubectl providers.
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

