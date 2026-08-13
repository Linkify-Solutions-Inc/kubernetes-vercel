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

variable "github_actions_thumbprints" {
  description = "TLS thumbprints of token.actions.githubusercontent.com. AWS accepts up to 5, so keep both the old and current after a rotation. Check with: echo | openssl s_client -servername token.actions.githubusercontent.com -connect token.actions.githubusercontent.com:443 | openssl x509 -fingerprint -noout -sha1"
  type        = list(string)
  default     = [
    "6938fd4d98bab03faadb97b34396831e3780aea1", # prior (pre-2026 rotation)
    "227203b5317f3818cab5b5ce596132bf36748c0e", # current (verified 2026-08-13)
  ]
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
