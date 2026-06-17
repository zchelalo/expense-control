locals {
  enable_interface_endpoints = (
    try(var.vpc_endpoints.ecr_api, false) ||
    try(var.vpc_endpoints.ecr_dkr, false)
  )

  interface_endpoints = {
    ecr_api = {
      service = "com.amazonaws.${var.region}.ecr.api"
      name    = "ecr-api-endpoint"
    }
    ecr_dkr = {
      service = "com.amazonaws.${var.region}.ecr.dkr"
      name    = "ecr-dkr-endpoint"
    }
  }

  tags = merge(
    var.tags,
    {
      Module = "vpc-endpoints"
    }
  )
}
