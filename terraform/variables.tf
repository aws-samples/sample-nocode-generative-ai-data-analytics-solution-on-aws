# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

variable "region" {
  type        = string
  description = "AWS region to be used"
}

variable "create_vpc" {
  type        = bool
  default     = false
  description = "Whether to deploy a example VPC, conflicts with vpc_config"
}

variable "vpc_config" {
  type = object({
    vpc_id             = string
    public_subnet_ids  = list(string)
    private_subnet_ids = list(string)
  })
  default     = null
  description = "VPC configuration object"
}

variable "s3_access_allowed_roles" {
  type        = list(string)
  default     = []
  description = "List of role ARNs that should be allowed access to the S3 bucket outside of the VPC endpoint"
}

variable "domain_name" {
  type        = string
  default     = null
  description = "Domain name for the ALB. If set, will set up an ALB, configure TLS certificate for the ALB (stored in ACM), and set up Route 53 alias, if the hosted_zone_id is set as well."
}

variable "hosted_zone_id" {
  type        = string
  default     = null
  description = "If hosted_zone_id is set and domain_name is set, will configure a Route 53 DNS entry for the ALB"
}

variable "lambda_environment_variables" {
  type        = map(string)
  description = "Map of environment variables that shall be passed to the lambda handler."
  default = {
    AWS_STS_REGIONAL_ENDPOINTS  = "regional"
    POWERTOOLS_LOG_LEVEL        = "DEBUG"
    POWERTOOLS_LOGGER_LOG_EVENT = "TRUE"
  }
}

variable "bedrock_inference_profile" {
  type        = string
  default     = null
  description = "The Bedrock Inference Profile to use with Bedrock Agents. Either this or bedrock_model_arn needs to be provided."
}

variable "bedrock_model_arn" {
  type        = string
  default     = null
  description = "The Bedrock Model ID to use with Bedrock Agents. Either this or bedrock_inference_profile needs to be provided."
}
