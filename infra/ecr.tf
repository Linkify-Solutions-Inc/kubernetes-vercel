# Private ECR repos for the five demo apps. Images are tagged immutably by
# commit SHA (see .github/workflows), so a tag is a version's identity for life.
resource "aws_ecr_repository" "apps" {
  for_each = toset(var.app_repositories)

  name                 = "mini-paas/${each.value}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}
