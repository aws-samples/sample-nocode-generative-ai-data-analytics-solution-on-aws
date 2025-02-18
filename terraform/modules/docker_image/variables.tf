# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

variable "ecr_kms_key_arn" {
  type        = string
  description = "KMS key ARN for ECR"
}

variable "region" {
  type        = string
  description = "AWS region"
}

variable "name" {
  type        = string
  description = "Name for the Docker image"
}

variable "build_context_path" {
  type        = string
  description = "Path to build context folder"
}

variable "dockerfile_path" {
  type        = string
  description = "Path to Dockerfile"
  default     = null
}
