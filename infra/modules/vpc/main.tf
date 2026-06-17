// VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(local.tags, {
    Name = "${var.name_prefix}-vpc"
  })
}

// Internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = merge(local.tags, {
    Name = "${var.name_prefix}-igw"
  })
}

// Public subnets
resource "aws_subnet" "public" {
  for_each                = toset(var.azs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, index(var.azs, each.key))
  availability_zone       = each.key
  map_public_ip_on_launch = true
  tags = merge(local.tags, {
    Name = "${var.name_prefix}-public-${each.key}"
  })
}

// Private subnets
resource "aws_subnet" "private" {
  for_each                = toset(var.azs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, length(var.azs) + index(var.azs, each.key))
  availability_zone       = each.key
  map_public_ip_on_launch = false
  tags = merge(local.tags, {
    Name = "${var.name_prefix}-private-${each.key}"
  })
}

// Route table for public
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags = merge(local.tags, {
    Name = "${var.name_prefix}-public-rt"
  })
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

// Private route tables
resource "aws_route_table" "private" {
  for_each = aws_subnet.private
  vpc_id   = aws_vpc.main.id
  tags = merge(local.tags, {
    Name = "${var.name_prefix}-private-rt-${each.key}"
  })
}

resource "aws_route_table_association" "private_assoc" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}