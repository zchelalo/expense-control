variable "project" {
  type        = string
  description = "Project name"
  nullable    = false
}

variable "environment" {
  type        = string
  description = "Environment (dev, stage, prod)"
  nullable    = false
}

variable "owner" {
  type        = string
  description = "Owner of the resources"
  nullable    = false
}

variable "environment_pretty" {
  type        = string
  description = "Pretty environment string (Development, Staging, Production)"
  nullable    = false
}

variable "cost_center" {
  type        = string
  description = "Cost center for the resources"
  nullable    = false
}