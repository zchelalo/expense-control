variable "project" {
  type        = string
  description = "Project name"
}

variable "owner" {
  type        = string
  description = "Owner of the resources"
}

variable "region" {
  type        = string
  description = "AWS region"
  nullable    = false
}

variable "environment" {
  type        = string
  description = "Deployment environment used for names, tags, and runtime configuration."
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "cost_center" {
  type        = string
  description = "Cost center for the resources"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  nullable    = false
}

variable "azs" {
  type        = list(string)
  description = "List of availability zones"
  nullable    = false
}

variable "app_base_url" {
  type        = string
  description = "Optional public URL for the application. If omitted, the ALB DNS name is used."
  default     = null
}

variable "route53_zone_name" {
  type        = string
  description = "Public Route 53 hosted zone name used for the application custom domain, for example chelalo.me."
  default     = null
}

variable "app_domain_name" {
  type        = string
  description = "Optional fully-qualified domain name for the application, for example expense-control-dev.chelalo.me."
  default     = null

  validation {
    condition     = (var.app_domain_name == null) == (var.route53_zone_name == null)
    error_message = "app_domain_name and route53_zone_name must be set together."
  }
}

variable "frontend_image" {
  type        = string
  description = "Container image URI for the Next.js frontend."
  nullable    = false
}

variable "backend_image" {
  type        = string
  description = "Container image URI for the Go backend."
  nullable    = false
}

variable "frontend_desired_count" {
  type        = number
  description = "Number of frontend tasks to run."
  default     = 1
}

variable "backend_desired_count" {
  type        = number
  description = "Number of backend tasks to run."
  default     = 1
}

variable "frontend_cpu" {
  type        = number
  description = "CPU units for the frontend ECS task."
  default     = 256
}

variable "frontend_memory" {
  type        = number
  description = "Memory in MiB for the frontend ECS task."
  default     = 512
}

variable "backend_cpu" {
  type        = number
  description = "CPU units for the backend ECS task."
  default     = 512
}

variable "backend_memory" {
  type        = number
  description = "Memory in MiB for the backend ECS task."
  default     = 1024
}

variable "db_name" {
  type        = string
  description = "Name of the PostgreSQL database to create."
  nullable    = false
}

variable "db_username" {
  type        = string
  description = "Master username for PostgreSQL."
  nullable    = false
}

variable "db_instance_class" {
  type        = string
  description = "RDS instance class for PostgreSQL."
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  type        = number
  description = "Initial PostgreSQL storage in GiB."
  default     = 20
}

variable "db_max_allocated_storage" {
  type        = number
  description = "Maximum PostgreSQL autoscaling storage in GiB."
  default     = 100
}

variable "db_engine_version" {
  type        = string
  description = "Optional PostgreSQL engine version."
  default     = null
}

variable "db_backup_retention_period" {
  type        = number
  description = "Number of days to retain database backups."
  default     = 7
}

variable "auth_session_secret_arn" {
  type        = string
  description = "Secrets Manager ARN containing the frontend session secret."
  nullable    = false
}

variable "jwt_access_private_key_secret_arn" {
  type        = string
  description = "Secrets Manager ARN containing the private JWT access key PEM."
  nullable    = false
}

variable "jwt_access_public_key_secret_arn" {
  type        = string
  description = "Secrets Manager ARN containing the public JWT access key PEM."
  nullable    = false
}

variable "jwt_refresh_private_key_secret_arn" {
  type        = string
  description = "Secrets Manager ARN containing the private JWT refresh key PEM."
  nullable    = false
}

variable "jwt_refresh_public_key_secret_arn" {
  type        = string
  description = "Secrets Manager ARN containing the public JWT refresh key PEM."
  nullable    = false
}

variable "backend_paginator_limit_default" {
  type        = number
  description = "Default pagination size for the backend."
  default     = 10
}

variable "access_token_ttl" {
  type        = string
  description = "Access token lifetime for the backend."
  default     = "15m"
}

variable "refresh_token_ttl" {
  type        = string
  description = "Refresh token lifetime for the backend."
  default     = "720h"
}

variable "otel_exporter_otlp_endpoint" {
  type        = string
  description = "Optional OTLP endpoint for trace export. Leave empty to disable external trace export."
  default     = ""
}

variable "otel_traces_sampler_ratio" {
  type        = number
  description = "Trace sampling ratio for backend spans. Use 1 to keep all traces."
  default     = 1

  validation {
    condition     = var.otel_traces_sampler_ratio >= 0 && var.otel_traces_sampler_ratio <= 1
    error_message = "otel_traces_sampler_ratio must be between 0 and 1."
  }
}

variable "enable_observability" {
  type        = bool
  description = "Whether to deploy the self-hosted observability stack in AWS."
  default     = false
}

variable "observability_allowed_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to access Grafana. Use your public IP with /32."
  default     = []
}

variable "observability_grafana_admin_user" {
  type        = string
  description = "Grafana admin username."
  default     = "admin"
}

variable "observability_grafana_cpu" {
  type        = number
  description = "CPU units for Grafana."
  default     = 256
}

variable "observability_grafana_memory" {
  type        = number
  description = "Memory in MiB for Grafana."
  default     = 512
}

variable "observability_prometheus_cpu" {
  type        = number
  description = "CPU units for Prometheus."
  default     = 512
}

variable "observability_prometheus_memory" {
  type        = number
  description = "Memory in MiB for Prometheus."
  default     = 1024
}

variable "observability_loki_cpu" {
  type        = number
  description = "CPU units for Loki."
  default     = 512
}

variable "observability_loki_memory" {
  type        = number
  description = "Memory in MiB for Loki."
  default     = 1024
}

variable "observability_tempo_cpu" {
  type        = number
  description = "CPU units for Tempo."
  default     = 512
}

variable "observability_tempo_memory" {
  type        = number
  description = "Memory in MiB for Tempo."
  default     = 1024
}

variable "observability_collector_cpu" {
  type        = number
  description = "CPU units for the OpenTelemetry Collector."
  default     = 256
}

variable "observability_collector_memory" {
  type        = number
  description = "Memory in MiB for the OpenTelemetry Collector."
  default     = 512
}

variable "additional_allowed_origins" {
  type        = list(string)
  description = "Additional allowed origins for the backend CORS configuration."
  default     = []
}
