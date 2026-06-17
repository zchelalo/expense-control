locals {
  tags = {
    Project     = var.project
    Environment = var.environment_pretty
    Owner       = var.owner
    CostCenter  = var.cost_center
    ManagedBy   = "Terraform"
  }
}
