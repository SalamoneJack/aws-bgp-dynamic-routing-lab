variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "key_pair" {
  description = "Name of an existing EC2 key pair for SSH access"
  type        = string
}

variable "cloud_cidr" {
  description = "CIDR block for the Cloud VPC (BGP AS 65001)"
  type        = string
  default     = "10.10.0.0/16"
}

variable "onprem_cidr" {
  description = "CIDR block for the OnPrem-Sim VPC (BGP AS 65002)"
  type        = string
  default     = "10.20.0.0/16"
}

variable "cloud_asn" {
  description = "BGP Autonomous System Number for the Cloud VPC"
  type        = number
  default     = 65001
}

variable "onprem_asn" {
  description = "BGP Autonomous System Number for the OnPrem-Sim VPC"
  type        = number
  default     = 65002
}

variable "instance_type" {
  description = "EC2 instance type for BGP router instances"
  type        = string
  default     = "t2.micro"
}
