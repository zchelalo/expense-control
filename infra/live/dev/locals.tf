locals {
  environment               = var.environment
  frontend_container_port   = 3000
  backend_container_port    = 8000
  postgres_port             = 5432
  grafana_container_port    = 3000
  prometheus_container_port = 9090
  loki_container_port       = 3100
  tempo_container_port      = 3200
  otel_grpc_container_port  = 4317
  otel_http_container_port  = 4318
  otel_metrics_port         = 8888

  frontend_service_name            = "${module.naming.name_prefix}-frontend"
  backend_service_name             = "${module.naming.name_prefix}-backend"
  cluster_name                     = "${module.naming.name_prefix}-cluster"
  database_identifier              = "${module.naming.name_prefix}-postgres"
  service_discovery_namespace_name = "${module.naming.name_prefix}.internal"

  observability_service_names = {
    backend        = "backend"
    grafana        = "grafana"
    prometheus     = "prometheus"
    loki           = "loki"
    tempo          = "tempo"
    otel_collector = "otel-collector"
  }

  observability_service_fqdns = {
    for key, value in local.observability_service_names :
    key => "${value}.${local.service_discovery_namespace_name}"
  }

  resolved_otel_exporter_otlp_endpoint = var.enable_observability ? "${local.observability_service_fqdns.otel_collector}:${local.otel_grpc_container_port}" : var.otel_exporter_otlp_endpoint

  firelens_image    = "public.ecr.aws/aws-observability/aws-for-fluent-bit:3"
  config_init_image = "public.ecr.aws/docker/library/busybox:1.36"

  observability_efs_paths = {
    grafana    = "/grafana"
    prometheus = "/prometheus"
    loki       = "/loki"
    tempo      = "/tempo"
  }

  public_app_base_url = trimsuffix(
    coalesce(var.app_base_url, "http://${aws_lb.app.dns_name}"),
    "/",
  )
  api_base_url    = "${local.public_app_base_url}/api"
  allowed_origins = distinct(concat([local.public_app_base_url], var.additional_allowed_origins))
}
