locals {
  project_slug = lower(replace(var.project, " ", "-"))

  environment_pretty = {
    dev   = "Development"
    stage = "Staging"
    prod  = "Production"
  }

  name_prefix = "${local.project_slug}-${var.environment}"
}
