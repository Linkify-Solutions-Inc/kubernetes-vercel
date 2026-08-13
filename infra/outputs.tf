output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}

output "region" {
  value = var.region
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}

output "ecr_repository_urls" {
  value = { for k, r in aws_ecr_repository.apps : k => r.repository_url }
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "node_iam_role_arn" {
  value = module.eks.node_iam_role_arn
}

output "node_iam_role_name" {
  value = module.eks.node_iam_role_name
}
