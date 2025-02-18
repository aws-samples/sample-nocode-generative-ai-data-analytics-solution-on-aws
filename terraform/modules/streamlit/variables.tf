# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

variable "ecs_kms_key_arn" {
  type        = string
  description = "KMS key ARN for ECS"
}

variable "region" {
  type        = string
  description = "AWS region"
}

variable "vpc_id" {
  type        = string
  description = "ID of the VPC the ALB should be deployed into"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs the ALB should be deployed into"
}

variable "alb_target_group_arn" {
  type        = string
  description = "ARN of the ALB target group for ECS"
}

variable "api_base_path" {
  type        = string
  description = "Base path for the API to be used by Streamlit"
}

variable "streamlit_src_path" {
  type        = string
  description = "Path to the source code of the Streamlit app"
}
