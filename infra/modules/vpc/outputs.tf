output "vpc_id" {
  value = aws_vpc.main.id
}

output "private_subnet_ids" {
  value = [for s in aws_subnet.private : s.id]
}

output "public_subnet_ids" {
  value = [for s in aws_subnet.public : s.id]
}

output "private_route_table_ids" {
  value = [for rt in aws_route_table.private : rt.id]
}

output "public_route_table_ids" {
  value = [aws_route_table.public.id]
}

output "vpc_cidr_block" {
  value = var.vpc_cidr
}

output "igw_id" {
  value = aws_internet_gateway.igw.id
}