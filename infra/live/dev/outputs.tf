output "alb_dns_name" {
  value = aws_lb.app.dns_name
}

output "frontend_url" {
  value = local.public_app_base_url
}

output "api_url" {
  value = local.api_base_url
}

output "frontend_ecr_repository_url" {
  value = aws_ecr_repository.frontend.repository_url
}

output "backend_ecr_repository_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "backend_service_name" {
  value = aws_ecs_service.backend.name
}

output "postgres_address" {
  value = aws_db_instance.postgres.address
}

output "postgres_master_secret_arn" {
  value = aws_db_instance.postgres.master_user_secret[0].secret_arn
}

output "service_discovery_namespace" {
  value = var.enable_observability ? aws_service_discovery_private_dns_namespace.internal[0].name : null
}

output "observability_enabled" {
  value = var.enable_observability
}

output "observability_grafana_url" {
  value = var.enable_observability ? "http://${aws_lb.observability[0].dns_name}" : null
}

output "observability_grafana_admin_user" {
  value = var.enable_observability ? var.observability_grafana_admin_user : null
}

output "observability_grafana_admin_password" {
  value     = var.enable_observability ? random_password.grafana_admin[0].result : null
  sensitive = true
}

output "observability_grafana_admin_password_secret_arn" {
  value = var.enable_observability ? aws_secretsmanager_secret.grafana_admin_password[0].arn : null
}

output "observability_otlp_endpoint_internal" {
  value = var.enable_observability ? local.resolved_otel_exporter_otlp_endpoint : null
}
