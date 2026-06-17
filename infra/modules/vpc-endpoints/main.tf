// VPC Endpoint for S3
resource "aws_vpc_endpoint" "s3" {
  for_each = { for k, v in var.vpc_endpoints : k => v if k == "s3" && v }

  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = var.private_route_table_ids

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-s3-endpoint"
  })
}

// Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints" {
  count = local.enable_interface_endpoints ? 1 : 0

  name        = "${var.name_prefix}-vpce-sg"
  description = "Security group for VPC interface endpoints"
  vpc_id      = var.vpc_id

  // Allow inbound HTTPS traffic from within the VPC
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-vpce-sg"
  })
}

// VPC Endpoint for ECR API and ECR DKR
resource "aws_vpc_endpoint" "interface" {
  for_each = {
    for k, cfg in local.interface_endpoints :
    k => cfg if try(var.vpc_endpoints[k], false)
  }

  vpc_id            = var.vpc_id
  vpc_endpoint_type = "Interface"
  service_name      = each.value.service

  subnet_ids          = var.private_subnet_ids
  security_group_ids  = aws_security_group.vpc_endpoints[*].id
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-${each.value.name}"
  })
}