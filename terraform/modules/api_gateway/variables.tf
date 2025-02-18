# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

variable "execute_api_vpce_id" {
  type        = string
  description = "ID of the VPC endpoint that is used to access API GW."
}

variable "domain_name" {
  type        = string
  description = "Domain name for the frontend."
}

variable "rest_api_spec" {
  description = "REST API specification to deploy the API Gateway from"
  type        = string
}

variable "logs_kms_key_arn" {
  type        = string
  description = "KMS key ARN for encryption of logs"
}
