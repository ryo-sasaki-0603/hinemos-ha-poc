variable "project" { type = string, default = "hinemos" }
variable "env"     { type = string, default = "poc" }

variable "region" { type = string, default = "ap-northeast-1" }
variable "az"     { type = string, default = "ap-northeast-1a" }

variable "vpc_cidr"          { type = string, default = "10.10.0.0/16" }
variable "public_subnet_cidr"{ type = string, default = "10.10.1.0/24" }

variable "my_ip_cidr" {
  description = "SSH許可元（例: 203.0.113.10/32）"
  type        = string
}

variable "key_name" {
  description = "既存のEC2キーペア名"
  type        = string
}

variable "mgr_instance_type" { type = string, default = "t2.medium" }
variable "db_instance_type"  { type = string, default = "t3.large" }

variable "root_volume_size"  { type = number, default = 25 }
variable "shared_ebs_size"   { type = number, default = 50 }

variable "vip_private_ip" {
  description = "VIP用のプライベートIP(サブネット内未使用IP)"
  type        = string
  default     = "10.10.1.200"
}