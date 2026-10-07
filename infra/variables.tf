variable "region" {
  type    = string
  default = "us-east-1"
}

variable "bucket_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "admin_cidr" {
  description = "203.205.17.217/32"
  type        = string
}

variable "ssh_public_key_path" {
  type = string
}

variable "github_repo" {
  type    = string
  default = "v1rtuos024/K4-L3L4-Track2-Day21-CI-CD-for-AI-Systems"
}

variable "github_oidc_provider_arn" {
  description = "ARN provider GitHub da co; de trong neu Terraform tao moi"
  type        = string
  default     = ""
}
