module "naming" {
  source = "../../modules/naming"

  project     = var.project
  environment = local.environment
}

module "tags" {
  source = "../../modules/tags"

  owner              = var.owner
  project            = var.project
  environment        = local.environment
  cost_center        = var.cost_center
  environment_pretty = module.naming.environment_pretty
}

module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr    = var.vpc_cidr
  azs         = var.azs
  name_prefix = module.naming.name_prefix
  region      = var.region
  tags        = module.tags.tags
}

data "aws_route53_zone" "app" {
  count        = local.use_custom_domain ? 1 : 0
  name         = "${trimsuffix(var.route53_zone_name, ".")}."
  private_zone = false
}

data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ecs_execution_secrets" {
  statement {
    actions = ["secretsmanager:GetSecretValue"]
    resources = concat([
      aws_db_instance.postgres.master_user_secret[0].secret_arn,
      var.auth_session_secret_arn,
      var.jwt_access_private_key_secret_arn,
      var.jwt_access_public_key_secret_arn,
      var.jwt_refresh_private_key_secret_arn,
      var.jwt_refresh_public_key_secret_arn,
      ], var.enable_observability ? [
      aws_secretsmanager_secret.grafana_admin_password[0].arn,
    ] : [])
  }
}

data "aws_iam_policy_document" "ecs_exec" {
  statement {
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role" "ecs_execution" {
  name               = "${module.naming.name_prefix}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
  tags               = module.tags.tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution_default" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name   = "${module.naming.name_prefix}-ecs-execution-secrets"
  role   = aws_iam_role.ecs_execution.id
  policy = data.aws_iam_policy_document.ecs_execution_secrets.json
}

resource "aws_iam_role_policy" "ecs_exec" {
  name   = "${module.naming.name_prefix}-ecs-exec"
  role   = aws_iam_role.ecs_execution.id
  policy = data.aws_iam_policy_document.ecs_exec.json
}

resource "aws_ecr_repository" "frontend" {
  name                 = local.frontend_service_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = module.tags.tags
}

resource "aws_ecr_repository" "backend" {
  name                 = local.backend_service_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = module.tags.tags
}

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/${local.frontend_service_name}"
  retention_in_days = 14
  tags              = module.tags.tags
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${local.backend_service_name}"
  retention_in_days = 14
  tags              = module.tags.tags
}

resource "aws_acm_certificate" "app" {
  count             = local.use_custom_domain ? 1 : 0
  domain_name       = var.app_domain_name
  validation_method = "DNS"
  tags              = module.tags.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "app_certificate_validation" {
  for_each = local.use_custom_domain ? {
    for dvo in aws_acm_certificate.app[0].domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.app[0].zone_id
}

resource "aws_acm_certificate_validation" "app" {
  count                   = local.use_custom_domain ? 1 : 0
  certificate_arn         = aws_acm_certificate.app[0].arn
  validation_record_fqdns = [for record in aws_route53_record.app_certificate_validation : record.fqdn]
}

resource "aws_ecs_cluster" "main" {
  name = local.cluster_name
  tags = module.tags.tags
}

resource "aws_security_group" "alb" {
  name        = "${module.naming.name_prefix}-alb"
  description = "Public ALB for Expense Control"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow inbound HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = local.use_custom_domain ? [1] : []

    content {
      description = "Allow inbound HTTPS"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
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

resource "aws_security_group" "frontend_service" {
  name        = "${module.naming.name_prefix}-frontend"
  description = "Frontend ECS tasks"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Allow traffic from the ALB"
    from_port       = local.frontend_container_port
    to_port         = local.frontend_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
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

resource "aws_security_group" "backend_service" {
  name        = "${module.naming.name_prefix}-backend"
  description = "Backend ECS tasks"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Allow traffic from the ALB"
    from_port       = local.backend_container_port
    to_port         = local.backend_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
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

resource "aws_security_group" "database" {
  name        = "${module.naming.name_prefix}-postgres"
  description = "PostgreSQL database access"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Allow backend access to PostgreSQL"
    from_port       = local.postgres_port
    to_port         = local.postgres_port
    protocol        = "tcp"
    security_groups = [aws_security_group.backend_service.id]
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

resource "aws_db_subnet_group" "postgres" {
  name       = "${module.naming.name_prefix}-postgres"
  subnet_ids = module.vpc.private_subnet_ids
  tags       = module.tags.tags
}

resource "aws_db_instance" "postgres" {
  identifier                  = local.database_identifier
  engine                      = "postgres"
  engine_version              = var.db_engine_version
  instance_class              = var.db_instance_class
  allocated_storage           = var.db_allocated_storage
  max_allocated_storage       = var.db_max_allocated_storage
  db_name                     = var.db_name
  username                    = var.db_username
  manage_master_user_password = true
  storage_encrypted           = true
  db_subnet_group_name        = aws_db_subnet_group.postgres.name
  vpc_security_group_ids      = [aws_security_group.database.id]
  backup_retention_period     = var.db_backup_retention_period
  apply_immediately           = true
  deletion_protection         = false
  skip_final_snapshot         = true
  publicly_accessible         = false
  copy_tags_to_snapshot       = true
  auto_minor_version_upgrade  = true
  multi_az                    = false
  port                        = local.postgres_port
  tags                        = module.tags.tags
}

resource "aws_lb" "app" {
  name               = "${module.naming.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnet_ids
  tags               = module.tags.tags
}

resource "aws_lb_target_group" "frontend" {
  name        = substr("${module.naming.name_prefix}-front", 0, 32)
  port        = local.frontend_container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = module.vpc.vpc_id

  health_check {
    enabled             = true
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200-399"
  }

  tags = module.tags.tags
}

resource "aws_lb_target_group" "backend" {
  name        = substr("${module.naming.name_prefix}-back", 0, 32)
  port        = local.backend_container_port
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
    matcher             = "200"
  }

  tags = module.tags.tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = local.use_custom_domain ? [1] : []

    content {
      type = "redirect"

      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = local.use_custom_domain ? [] : [1]

    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.frontend.arn
    }
  }
}

resource "aws_lb_listener" "https" {
  count             = local.use_custom_domain ? 1 : 0
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.app[0].certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

resource "aws_lb_listener_rule" "api" {
  listener_arn = local.use_custom_domain ? aws_lb_listener.https[0].arn : aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}

resource "aws_lb_listener_rule" "metrics_block" {
  listener_arn = local.use_custom_domain ? aws_lb_listener.https[0].arn : aws_lb_listener.http.arn
  priority     = 50

  action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "forbidden"
      status_code  = "403"
    }
  }

  condition {
    path_pattern {
      values = ["/api/metrics", "/api/metrics/*"]
    }
  }
}

resource "aws_route53_record" "app" {
  count   = local.use_custom_domain ? 1 : 0
  zone_id = data.aws_route53_zone.app[0].zone_id
  name    = var.app_domain_name
  type    = "A"

  alias {
    name                   = aws_lb.app.dns_name
    zone_id                = aws_lb.app.zone_id
    evaluate_target_health = true
  }
}

resource "aws_ecs_task_definition" "frontend" {
  family                   = local.frontend_service_name
  cpu                      = tostring(var.frontend_cpu)
  memory                   = tostring(var.frontend_memory)
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_execution.arn

  container_definitions = jsonencode(concat([
    merge({
      name      = "frontend"
      image     = var.frontend_image
      essential = true
      portMappings = [
        {
          containerPort = local.frontend_container_port
          hostPort      = local.frontend_container_port
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "NODE_ENV"
          value = "production"
        },
        {
          name  = "PORT"
          value = tostring(local.frontend_container_port)
        },
        {
          name  = "HOSTNAME"
          value = "0.0.0.0"
        },
        {
          name  = "API_URL"
          value = local.api_base_url
        },
        {
          name  = "NEXT_PUBLIC_API_URL"
          value = local.api_base_url
        },
        {
          name  = "AUTH_SECURE_COOKIES"
          value = tostring(startswith(local.public_app_base_url, "https://"))
        }
      ]
      secrets = [
        {
          name      = "AUTH_SESSION_SECRET"
          valueFrom = var.auth_session_secret_arn
        }
      ]
      }, {
      dependsOn = var.enable_observability ? [
        {
          containerName = "log-router"
          condition     = "START"
        }
      ] : []
      logConfiguration = var.enable_observability ? {
        logDriver = "awsfirelens"
        options = {
          Name        = "loki"
          host        = local.observability_service_fqdns.loki
          port        = tostring(local.loki_container_port)
          labels      = "service=${local.frontend_service_name},environment=${local.environment}"
          line_format = "json"
        }
        } : {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.frontend.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
    })
    ], var.enable_observability ? [
    {
      name      = "log-router"
      image     = local.firelens_image
      essential = true
      firelensConfiguration = {
        type = "fluentbit"
        options = {
          "enable-ecs-log-metadata" = "true"
        }
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.frontend.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "firelens"
        }
      }
    }
  ] : []))

  tags = module.tags.tags
}

resource "aws_ecs_task_definition" "backend" {
  family                   = local.backend_service_name
  cpu                      = tostring(var.backend_cpu)
  memory                   = tostring(var.backend_memory)
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_execution.arn

  container_definitions = jsonencode(concat([
    merge({
      name      = "backend"
      image     = var.backend_image
      essential = true
      portMappings = [
        {
          containerPort = local.backend_container_port
          hostPort      = local.backend_container_port
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "ENVIRONMENT"
          value = "production"
        },
        {
          name  = "SERVICE_NAME"
          value = "expense-control-back"
        },
        {
          name  = "PORT"
          value = tostring(local.backend_container_port)
        },
        {
          name  = "DB_HOST"
          value = aws_db_instance.postgres.address
        },
        {
          name  = "DB_USER"
          value = var.db_username
        },
        {
          name  = "DB_NAME"
          value = var.db_name
        },
        {
          name  = "DB_PORT"
          value = tostring(local.postgres_port)
        },
        {
          name  = "AUTO_RUN_MIGRATIONS"
          value = "true"
        },
        {
          name  = "PAGINATOR_LIMIT_DEFAULT"
          value = tostring(var.backend_paginator_limit_default)
        },
        {
          name  = "ALLOWED_ORIGINS"
          value = join(",", local.allowed_origins)
        },
        {
          name  = "ACCESS_TOKEN_TTL"
          value = var.access_token_ttl
        },
        {
          name  = "REFRESH_TOKEN_TTL"
          value = var.refresh_token_ttl
        },
        {
          name  = "OTEL_EXPORTER_OTLP_ENDPOINT"
          value = local.resolved_otel_exporter_otlp_endpoint
        },
        {
          name  = "OTEL_TRACES_SAMPLER_RATIO"
          value = tostring(var.otel_traces_sampler_ratio)
        },
        {
          name  = "JWT_ACCESS_PRIVATE_KEY_PATH"
          value = "/run/secrets/jwt/private_access.pem"
        },
        {
          name  = "JWT_ACCESS_PUBLIC_KEY_PATH"
          value = "/run/secrets/jwt/public_access.pem"
        },
        {
          name  = "JWT_REFRESH_PRIVATE_KEY_PATH"
          value = "/run/secrets/jwt/private_refresh.pem"
        },
        {
          name  = "JWT_REFRESH_PUBLIC_KEY_PATH"
          value = "/run/secrets/jwt/public_refresh.pem"
        }
      ]
      secrets = [
        {
          name      = "DB_PASS"
          valueFrom = "${aws_db_instance.postgres.master_user_secret[0].secret_arn}:password::"
        },
        {
          name      = "JWT_ACCESS_PRIVATE_KEY"
          valueFrom = var.jwt_access_private_key_secret_arn
        },
        {
          name      = "JWT_ACCESS_PUBLIC_KEY"
          valueFrom = var.jwt_access_public_key_secret_arn
        },
        {
          name      = "JWT_REFRESH_PRIVATE_KEY"
          valueFrom = var.jwt_refresh_private_key_secret_arn
        },
        {
          name      = "JWT_REFRESH_PUBLIC_KEY"
          valueFrom = var.jwt_refresh_public_key_secret_arn
        }
      ]
      }, {
      dependsOn = var.enable_observability ? [
        {
          containerName = "log-router"
          condition     = "START"
        }
      ] : []
      logConfiguration = var.enable_observability ? {
        logDriver = "awsfirelens"
        options = {
          Name        = "loki"
          host        = local.observability_service_fqdns.loki
          port        = tostring(local.loki_container_port)
          labels      = "service=${local.backend_service_name},environment=${local.environment}"
          line_format = "json"
        }
        } : {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.backend.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
    })
    ], var.enable_observability ? [
    {
      name      = "log-router"
      image     = local.firelens_image
      essential = true
      firelensConfiguration = {
        type = "fluentbit"
        options = {
          "enable-ecs-log-metadata" = "true"
        }
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.backend.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "firelens"
        }
      }
    }
  ] : []))

  tags = module.tags.tags
}

resource "aws_ecs_service" "frontend" {
  name                               = local.frontend_service_name
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.frontend.arn
  desired_count                      = var.frontend_desired_count
  launch_type                        = "FARGATE"
  enable_execute_command             = true
  health_check_grace_period_seconds  = 60
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = module.vpc.public_subnet_ids
    security_groups  = [aws_security_group.frontend_service.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "frontend"
    container_port   = local.frontend_container_port
  }

  depends_on = [aws_lb_listener.http]
  tags       = module.tags.tags
}

resource "aws_ecs_service" "backend" {
  name                               = local.backend_service_name
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.backend.arn
  desired_count                      = var.backend_desired_count
  launch_type                        = "FARGATE"
  enable_execute_command             = true
  health_check_grace_period_seconds  = 60
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = module.vpc.public_subnet_ids
    security_groups  = [aws_security_group.backend_service.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = local.backend_container_port
  }

  dynamic "service_registries" {
    for_each = var.enable_observability ? [aws_service_discovery_service.backend[0].arn] : []

    content {
      registry_arn = service_registries.value
    }
  }

  depends_on = [
    aws_db_instance.postgres,
    aws_lb_listener_rule.api,
  ]
  tags = module.tags.tags
}
