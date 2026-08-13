variable "region" {
  description = "AWS region for the platform."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
  default     = "mini-paas"
}

variable "cluster_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.31"
}

variable "vpc_cidr" {
  description = "CIDR for the platform VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones to build subnets in."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "node_instance_type" {
  description = "Instance type for the bootstrap node group."
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  type    = number
  default = 1
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 2
}

variable "github_org" {
  description = "GitHub organization/owner of the repository (OIDC trust scope)."
  type        = string
  default     = "Linkify-Solutions-Inc"
}

variable "github_repo" {
  description = "GitHub repository name (OIDC trust scope)."
  type        = string
  default     = "kubernetes-vercel"
}

variable "github_actions_thumbprint" {
  description = "TLS thumbprint of token.actions.githubusercontent.com. Check with openssl s_client if a renewal lands."
  type        = string
  default     = "6938fd4d98bab03faadb97b34396831e3780aea1"
}

variable "app_repositories" {
  description = "Demo application ECR repositories (one per demo app)."
  type        = list(string)
  default     = ["api-node", "web-node", "worker-node", "py-api", "go-api"]
}

variable "karpenter_version" {
  description = "Karpenter helm chart version."
  type        = string
  default     = "1.6.0"
}

variable "karpenter_instance_types" {
  description = "Instance types Karpenter may provision."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "karpenter_capacity_type" {
  description = "on-demand or spot."
  type        = string
  default     = "on-demand"
}

variable "tags" {
  description = "Extra tags applied to all resources."
  type        = map(string)
  default     = {}
}
