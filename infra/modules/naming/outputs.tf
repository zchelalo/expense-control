output "project_slug" {
  value = local.project_slug
}

output "environment_pretty" {
  value = local.environment_pretty[var.environment]
}

output "name_prefix" {
  value = local.name_prefix
}
