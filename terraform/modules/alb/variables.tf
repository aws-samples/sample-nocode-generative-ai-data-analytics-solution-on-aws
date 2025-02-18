# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

variable "vpc_id" {
  type        = string
  description = "ID of the VPC the ALB should be deployed into"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs the ALB should be deployed into"
}

variable "s3_vpce_id" {
  type        = string
  description = "ID of the S3 VPC endpoint"
}

variable "s3_vpce_nr_ips" {
  type        = number
  description = "Number of IPs (= subnets) for the S3 VPC endpoint"
}

variable "execute_api_vpce_id" {
  type        = string
  description = "ID of the execute-api VPC endpoint"
}

variable "execute_api_vpce_nr_ips" {
  type        = number
  description = "Number of IPs (= subnets) for the execute-api VPC endpoint"
}

variable "private_subnet_cidr_blocks" {
  type        = list(string)
  description = "List of CIDR blocks for the streamlit subnets"
}

variable "logs_kms_key_arn" {
  type        = string
  description = "KMS key ARN for encryption of logs"
}

variable "domain_name" {
  type        = string
  description = "Domain name that should be associated with the ALB"
}

variable "hosted_zone_id" {
  type        = string
  default     = null
  description = "If set and domain_name is set, will configure a Route 53 DNS entry for the ALB"
}

variable "log_bucket_name" {
  type        = string
  description = "Name of the S3 bucket for storing access logs"
}
