variable "vpc_cidr" {
  type        = string
  description = "The CIDR block for the VPC"
  nullable    = false
}

variable "azs" {
  type        = list(string)
  description = "A list of availability zones to use for the subnets"
  nullable    = false
}

variable "region" {
  type        = string
  description = "AWS region where the VPC will be created"
  nullable    = false
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
