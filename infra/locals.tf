locals {
  name = var.cluster_name
  azs  = var.azs

  tags = merge({
    Project   = "mini-paas"
    ManagedBy = "terraform"
  }, var.tags)
}
