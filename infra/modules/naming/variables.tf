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
