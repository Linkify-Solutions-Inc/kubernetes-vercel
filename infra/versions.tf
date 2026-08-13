terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.34"
    }
  }

  # Remote state lives in S3, locked by DynamoDB.
  # Bootstrap once with ./bootstrap-state.sh, then:
  #   terraform init -backend-config=backend.tfvars
  backend "s3" {}
}
