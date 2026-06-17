locals {
  observability_config_grafana_datasources = templatefile("${path.root}/../../../observability/aws/grafana-datasources.yml.tftpl", {
    prometheus_host = local.observability_service_fqdns.prometheus
    loki_host       = local.observability_service_fqdns.loki
    tempo_host      = local.observability_service_fqdns.tempo
  })
  observability_config_grafana_datasources_base64 = base64encode(local.observability_config_grafana_datasources)

  observability_config_prometheus = templatefile("${path.root}/../../../observability/aws/prometheus.yml.tftpl", {
    backend_host        = local.observability_service_fqdns.backend
    backend_port        = local.backend_container_port
    otel_collector_host = local.observability_service_fqdns.otel_collector
    otel_metrics_port   = local.otel_metrics_port
  })
  observability_config_prometheus_base64 = base64encode(local.observability_config_prometheus)

  observability_config_loki        = file("${path.root}/../../../observability/aws/loki-config.yml")
  observability_config_loki_base64 = base64encode(local.observability_config_loki)

  observability_config_tempo        = file("${path.root}/../../../observability/aws/tempo-config.yml")
  observability_config_tempo_base64 = base64encode(local.observability_config_tempo)

  observability_config_otel_collector = templatefile("${path.root}/../../../observability/aws/otel-collector-config.yml.tftpl", {
    tempo_host = local.observability_service_fqdns.tempo
    tempo_port = local.otel_grpc_container_port
  })
  observability_config_otel_collector_base64 = base64encode(local.observability_config_otel_collector)

  observability_discovery_services = var.enable_observability ? {
    for key, value in local.observability_service_names :
    key => value if key != "backend"
  } : {}

  observability_log_groups = var.enable_observability ? toset([
    "grafana",
    "prometheus",
    "loki",
    "tempo",
    "otel-collector",
  ]) : toset([])
}

resource "aws_service_discovery_private_dns_namespace" "internal" {
  count = var.enable_observability ? 1 : 0

  name = local.service_discovery_namespace_name
  vpc  = module.vpc.vpc_id
  tags = module.tags.tags
}

resource "aws_service_discovery_service" "backend" {
  count = var.enable_observability ? 1 : 0

  name = local.observability_service_names.backend

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.internal[0].id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
  }
}

resource "aws_service_discovery_service" "observability" {
  for_each = local.observability_discovery_services

  name = each.value

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.internal[0].id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
  }
}

resource "random_password" "grafana_admin" {
  count = var.enable_observability ? 1 : 0

  length           = 24
  special          = true
  override_special = "!@#%^*-_=+"
}

resource "aws_secretsmanager_secret" "grafana_admin_password" {
  count = var.enable_observability ? 1 : 0

  name                    = "${module.naming.name_prefix}/observability/grafana-admin-password"
  recovery_window_in_days = 0
  tags                    = module.tags.tags
}

resource "aws_secretsmanager_secret_version" "grafana_admin_password" {
  count = var.enable_observability ? 1 : 0

  secret_id     = aws_secretsmanager_secret.grafana_admin_password[0].id
  secret_string = random_password.grafana_admin[0].result
}

resource "aws_cloudwatch_log_group" "observability" {
  for_each = local.observability_log_groups

  name              = "/ecs/${module.naming.name_prefix}-${each.key}"
  retention_in_days = 14
  tags              = module.tags.tags
}

resource "aws_security_group" "observability_alb" {
  count = var.enable_observability ? 1 : 0

  name        = "${module.naming.name_prefix}-observability-alb"
  description = "Restricted public ALB for Grafana"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow Grafana access only from approved CIDRs"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = length(var.observability_allowed_cidrs) > 0 ? var.observability_allowed_cidrs : ["127.255.255.255/32"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    precondition {
      condition     = length(var.observability_allowed_cidrs) > 0
      error_message = "Set at least one observability_allowed_cidr when enable_observability is true."
    }
  }

  tags = module.tags.tags
}

resource "aws_security_group" "grafana_service" {
  count = var.enable_observability ? 1 : 0

  name        = "${module.naming.name_prefix}-grafana"
  description = "Grafana ECS tasks"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Allow traffic from the observability ALB"
    from_port       = local.grafana_container_port
    to_port         = local.grafana_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.observability_alb[0].id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = module.tags.tags
}

resource "aws_security_group" "observability_internal" {
  count = var.enable_observability ? 1 : 0

  name        = "${module.naming.name_prefix}-observability"
  description = "Internal observability services"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow internal observability traffic"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description     = "Allow app tasks to send logs to Loki"
    from_port       = local.loki_container_port
    to_port         = local.loki_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend_service.id, aws_security_group.backend_service.id]
  }

  ingress {
    description     = "Allow app tasks to export traces via OTLP gRPC"
    from_port       = local.otel_grpc_container_port
    to_port         = local.otel_grpc_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend_service.id, aws_security_group.backend_service.id]
  }

  ingress {
    description     = "Allow app tasks to export traces via OTLP HTTP"
    from_port       = local.otel_http_container_port
    to_port         = local.otel_http_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend_service.id, aws_security_group.backend_service.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = module.tags.tags
}

resource "aws_security_group_rule" "backend_metrics_from_observability" {
  count = var.enable_observability ? 1 : 0

  type                     = "ingress"
  from_port                = local.backend_container_port
  to_port                  = local.backend_container_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.backend_service.id
  source_security_group_id = aws_security_group.observability_internal[0].id
  description              = "Allow Prometheus to scrape backend metrics"
}

resource "aws_security_group" "observability_efs" {
  count = var.enable_observability ? 1 : 0

  name        = "${module.naming.name_prefix}-observability-efs"
  description = "EFS access for observability services"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Allow NFS from observability tasks"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.observability_internal[0].id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = module.tags.tags
}

resource "aws_efs_file_system" "observability" {
  count = var.enable_observability ? 1 : 0

  encrypted        = true
  throughput_mode  = "elastic"
  performance_mode = "generalPurpose"
  tags = merge(module.tags.tags, {
    Name = "${module.naming.name_prefix}-observability"
  })
}

resource "aws_efs_mount_target" "observability" {
  for_each = var.enable_observability ? {
    for subnet_id in module.vpc.public_subnet_ids : subnet_id => subnet_id
  } : {}

  file_system_id  = aws_efs_file_system.observability[0].id
  subnet_id       = each.value
  security_groups = [aws_security_group.observability_efs[0].id]
}

resource "aws_efs_access_point" "observability" {
  for_each = var.enable_observability ? local.observability_efs_paths : {}

  file_system_id = aws_efs_file_system.observability[0].id

  posix_user {
    uid = 0
    gid = 0
  }

  root_directory {
    path = each.value

    creation_info {
      owner_gid   = 0
      owner_uid   = 0
      permissions = "0775"
    }
  }

  tags = merge(module.tags.tags, {
    Name = "${module.naming.name_prefix}-${each.key}"
  })
}

resource "aws_lb" "observability" {
  count = var.enable_observability ? 1 : 0

  name               = substr("${module.naming.name_prefix}-obs-alb", 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.observability_alb[0].id]
  subnets            = module.vpc.public_subnet_ids

  lifecycle {
    precondition {
      condition     = length(var.observability_allowed_cidrs) > 0
      error_message = "Set observability_allowed_cidrs before enabling observability."
    }
  }

  tags = module.tags.tags
}

resource "aws_lb_target_group" "grafana" {
  count = var.enable_observability ? 1 : 0

  name        = substr("${module.naming.name_prefix}-grafana", 0, 32)
  port        = local.grafana_container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = module.vpc.vpc_id

  health_check {
    enabled             = true
    path                = "/api/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200-399"
  }

  tags = module.tags.tags
}

resource "aws_lb_listener" "observability_http" {
  count = var.enable_observability ? 1 : 0

  load_balancer_arn = aws_lb.observability[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana[0].arn
  }
}

resource "aws_ecs_task_definition" "grafana" {
  count = var.enable_observability ? 1 : 0

  family                   = "${module.naming.name_prefix}-grafana"
  cpu                      = tostring(var.observability_grafana_cpu)
  memory                   = tostring(var.observability_grafana_memory)
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_execution.arn

  volume {
    name = "config"
  }

  volume {
    name = "data"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.observability[0].id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = aws_efs_access_point.observability["grafana"].id
        iam             = "DISABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "config-init"
      image     = local.config_init_image
      essential = false
      command = [
        "/bin/sh",
        "-ec",
        "mkdir -p /config && printf '%s' '${local.observability_config_grafana_datasources_base64}' | base64 -d > /config/datasources.yml",
      ]
      mountPoints = [
        {
          sourceVolume  = "config"
          containerPath = "/config"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.observability["grafana"].name
          awslogs-region        = var.region
          awslogs-stream-prefix = "config"
        }
      }
    },
    {
      name      = "grafana"
      image     = "grafana/grafana:12.1.1"
      essential = true
      portMappings = [
        {
          containerPort = local.grafana_container_port
          hostPort      = local.grafana_container_port
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "GF_SECURITY_ADMIN_USER"
          value = var.observability_grafana_admin_user
        }
      ]
      secrets = [
        {
          name      = "GF_SECURITY_ADMIN_PASSWORD"
          valueFrom = aws_secretsmanager_secret.grafana_admin_password[0].arn
        }
      ]
      dependsOn = [
        {
          containerName = "config-init"
          condition     = "SUCCESS"
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "config"
          containerPath = "/etc/grafana/provisioning/datasources"
          readOnly      = true
        },
        {
          sourceVolume  = "data"
          containerPath = "/var/lib/grafana"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.observability["grafana"].name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = module.tags.tags
}

resource "aws_ecs_task_definition" "prometheus" {
  count = var.enable_observability ? 1 : 0

  family                   = "${module.naming.name_prefix}-prometheus"
  cpu                      = tostring(var.observability_prometheus_cpu)
  memory                   = tostring(var.observability_prometheus_memory)
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_execution.arn

  volume {
    name = "config"
  }

  volume {
    name = "data"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.observability[0].id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = aws_efs_access_point.observability["prometheus"].id
        iam             = "DISABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "config-init"
      image     = local.config_init_image
      essential = false
      command = [
        "/bin/sh",
        "-ec",
        "mkdir -p /config && printf '%s' '${local.observability_config_prometheus_base64}' | base64 -d > /config/prometheus.yml",
      ]
      mountPoints = [
        {
          sourceVolume  = "config"
          containerPath = "/config"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.observability["prometheus"].name
          awslogs-region        = var.region
          awslogs-stream-prefix = "config"
        }
      }
    },
    {
      name      = "prometheus"
      image     = "prom/prometheus:v3.5.0"
      essential = true
      portMappings = [
        {
          containerPort = local.prometheus_container_port
          hostPort      = local.prometheus_container_port
          protocol      = "tcp"
        }
      ]
      command = [
        "--config.file=/etc/prometheus/prometheus.yml",
        "--storage.tsdb.path=/prometheus",
      ]
      dependsOn = [
        {
          containerName = "config-init"
          condition     = "SUCCESS"
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "config"
          containerPath = "/etc/prometheus"
          readOnly      = true
        },
        {
          sourceVolume  = "data"
          containerPath = "/prometheus"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.observability["prometheus"].name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = module.tags.tags
}

resource "aws_ecs_task_definition" "loki" {
  count = var.enable_observability ? 1 : 0

  family                   = "${module.naming.name_prefix}-loki"
  cpu                      = tostring(var.observability_loki_cpu)
  memory                   = tostring(var.observability_loki_memory)
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_execution.arn

  volume {
    name = "config"
  }

  volume {
    name = "data"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.observability[0].id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = aws_efs_access_point.observability["loki"].id
        iam             = "DISABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "config-init"
      image     = local.config_init_image
      essential = false
      command = [
        "/bin/sh",
        "-ec",
        "mkdir -p /config && printf '%s' '${local.observability_config_loki_base64}' | base64 -d > /config/config.yml",
      ]
      mountPoints = [
        {
          sourceVolume  = "config"
          containerPath = "/config"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.observability["loki"].name
          awslogs-region        = var.region
          awslogs-stream-prefix = "config"
        }
      }
    },
    {
      name      = "loki"
      image     = "grafana/loki:3.5.3"
      essential = true
      portMappings = [
        {
          containerPort = local.loki_container_port
          hostPort      = local.loki_container_port
          protocol      = "tcp"
        }
      ]
      command = ["-config.file=/etc/loki/config.yml"]
      dependsOn = [
        {
          containerName = "config-init"
          condition     = "SUCCESS"
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "config"
          containerPath = "/etc/loki"
          readOnly      = true
        },
        {
          sourceVolume  = "data"
          containerPath = "/loki"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.observability["loki"].name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = module.tags.tags
}

resource "aws_ecs_task_definition" "tempo" {
  count = var.enable_observability ? 1 : 0

  family                   = "${module.naming.name_prefix}-tempo"
  cpu                      = tostring(var.observability_tempo_cpu)
  memory                   = tostring(var.observability_tempo_memory)
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_execution.arn

  volume {
    name = "config"
  }

  volume {
    name = "data"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.observability[0].id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = aws_efs_access_point.observability["tempo"].id
        iam             = "DISABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "config-init"
      image     = local.config_init_image
      essential = false
      command = [
        "/bin/sh",
        "-ec",
        "mkdir -p /config && printf '%s' '${local.observability_config_tempo_base64}' | base64 -d > /config/config.yml",
      ]
      mountPoints = [
        {
          sourceVolume  = "config"
          containerPath = "/config"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.observability["tempo"].name
          awslogs-region        = var.region
          awslogs-stream-prefix = "config"
        }
      }
    },
    {
      name      = "tempo"
      image     = "grafana/tempo:2.8.2"
      essential = true
      portMappings = [
        {
          containerPort = local.tempo_container_port
          hostPort      = local.tempo_container_port
          protocol      = "tcp"
        },
        {
          containerPort = local.otel_grpc_container_port
          hostPort      = local.otel_grpc_container_port
          protocol      = "tcp"
        }
      ]
      command = ["-config.file=/etc/tempo/config.yml"]
      dependsOn = [
        {
          containerName = "config-init"
          condition     = "SUCCESS"
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "config"
          containerPath = "/etc/tempo"
          readOnly      = true
        },
        {
          sourceVolume  = "data"
          containerPath = "/tmp/tempo"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.observability["tempo"].name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = module.tags.tags
}

resource "aws_ecs_task_definition" "otel_collector" {
  count = var.enable_observability ? 1 : 0

  family                   = "${module.naming.name_prefix}-otel-collector"
  cpu                      = tostring(var.observability_collector_cpu)
  memory                   = tostring(var.observability_collector_memory)
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_execution.arn

  volume {
    name = "config"
  }

  container_definitions = jsonencode([
    {
      name      = "config-init"
      image     = local.config_init_image
      essential = false
      command = [
        "/bin/sh",
        "-ec",
        "mkdir -p /config && printf '%s' '${local.observability_config_otel_collector_base64}' | base64 -d > /config/config.yml",
      ]
      mountPoints = [
        {
          sourceVolume  = "config"
          containerPath = "/config"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.observability["otel-collector"].name
          awslogs-region        = var.region
          awslogs-stream-prefix = "config"
        }
      }
    },
    {
      name      = "otel-collector"
      image     = "otel/opentelemetry-collector-contrib:0.130.1"
      essential = true
      portMappings = [
        {
          containerPort = local.otel_grpc_container_port
          hostPort      = local.otel_grpc_container_port
          protocol      = "tcp"
        },
        {
          containerPort = local.otel_http_container_port
          hostPort      = local.otel_http_container_port
          protocol      = "tcp"
        },
        {
          containerPort = local.otel_metrics_port
          hostPort      = local.otel_metrics_port
          protocol      = "tcp"
        }
      ]
      command = ["--config=/etc/otelcol/config.yml"]
      dependsOn = [
        {
          containerName = "config-init"
          condition     = "SUCCESS"
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "config"
          containerPath = "/etc/otelcol"
          readOnly      = true
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.observability["otel-collector"].name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = module.tags.tags
}

resource "aws_ecs_service" "grafana" {
  count = var.enable_observability ? 1 : 0

  name                               = "${module.naming.name_prefix}-grafana"
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.grafana[0].arn
  desired_count                      = 1
  launch_type                        = "FARGATE"
  enable_execute_command             = true
  health_check_grace_period_seconds  = 60
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = module.vpc.public_subnet_ids
    security_groups  = [aws_security_group.grafana_service[0].id, aws_security_group.observability_internal[0].id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.grafana[0].arn
    container_name   = "grafana"
    container_port   = local.grafana_container_port
  }

  service_registries {
    registry_arn = aws_service_discovery_service.observability["grafana"].arn
  }

  depends_on = [
    aws_efs_mount_target.observability,
    aws_lb_listener.observability_http,
  ]
  tags = module.tags.tags
}

resource "aws_ecs_service" "prometheus" {
  count = var.enable_observability ? 1 : 0

  name                               = "${module.naming.name_prefix}-prometheus"
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.prometheus[0].arn
  desired_count                      = 1
  launch_type                        = "FARGATE"
  enable_execute_command             = true
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = module.vpc.public_subnet_ids
    security_groups  = [aws_security_group.observability_internal[0].id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.observability["prometheus"].arn
  }

  depends_on = [aws_efs_mount_target.observability]
  tags       = module.tags.tags
}

resource "aws_ecs_service" "loki" {
  count = var.enable_observability ? 1 : 0

  name                               = "${module.naming.name_prefix}-loki"
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.loki[0].arn
  desired_count                      = 1
  launch_type                        = "FARGATE"
  enable_execute_command             = true
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = module.vpc.public_subnet_ids
    security_groups  = [aws_security_group.observability_internal[0].id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.observability["loki"].arn
  }

  depends_on = [aws_efs_mount_target.observability]
  tags       = module.tags.tags
}

resource "aws_ecs_service" "tempo" {
  count = var.enable_observability ? 1 : 0

  name                               = "${module.naming.name_prefix}-tempo"
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.tempo[0].arn
  desired_count                      = 1
  launch_type                        = "FARGATE"
  enable_execute_command             = true
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = module.vpc.public_subnet_ids
    security_groups  = [aws_security_group.observability_internal[0].id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.observability["tempo"].arn
  }

  depends_on = [aws_efs_mount_target.observability]
  tags       = module.tags.tags
}

resource "aws_ecs_service" "otel_collector" {
  count = var.enable_observability ? 1 : 0

  name                               = "${module.naming.name_prefix}-otel-collector"
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.otel_collector[0].arn
  desired_count                      = 1
  launch_type                        = "FARGATE"
  enable_execute_command             = true
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = module.vpc.public_subnet_ids
    security_groups  = [aws_security_group.observability_internal[0].id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.observability["otel_collector"].arn
  }

  tags = module.tags.tags
}
