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
  default     = "1.36"
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
  description = "SHA-1 thumbprints of GitHub's OIDC TOKEN-SIGNING certificates (from the JWKS at token.actions.githubusercontent.com/.well-known/jwks). AWS accepts up to 5, so keep old + current across a rotation. Note: this is NOT the TLS leaf cert — verify with: curl -s https://token.actions.githubusercontent.com/.well-known/jwks | jq -r '.keys[].x5c[0]' | while read c; do echo \"$c\" | base64 -d | openssl x509 -inform DER -fingerprint -noout -sha1; done"
  type        = list(string)
  default = [
    "6938fd4d98bab03faadb97b34396831e3780aea1", # prior signing key (retired by GitHub 2026)
    "ca435a638a8cfed6b89364e064e08460b91c6250", # current signing key (from JWKS, verified 2026-08-13)
    "38e9b30b3a023a1b72309921a69a42fcc496c42c", # current signing key
    "4f3e9ad8c9a6f5eb3173006f4fa630e28f43dce9", # current signing key
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
