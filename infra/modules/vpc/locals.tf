locals {
  private_subnet_ids      = [for subnet in aws_subnet.private : subnet.id]
  private_route_table_ids = [for rt in aws_route_table.private : rt.id]

  tags = merge(
    var.tags,
    {
      Module = "vpc"
    }
  )
}
