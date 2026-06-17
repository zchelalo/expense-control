variable "region" {
  type        = string
  description = "AWS Region"
  nullable    = false
}

variable "vpc_id" {
  type        = string
  description = "The ID of the VPC where endpoints will be created"
  nullable    = false
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block of the VPC"
  nullable    = false
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "List of private subnet IDs for interface endpoints"
  nullable    = false
}

variable "private_route_table_ids" {
  type        = list(string)
  description = "List of private route table IDs for gateway endpoints"
  nullable    = false
}

variable "vpc_endpoints" {
  type = map(bool)
  default = {
    s3      = true
    ecr_api = true
    ecr_dkr = true
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names"
  nullable    = false
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to assign to resources"
  nullable    = false
}
