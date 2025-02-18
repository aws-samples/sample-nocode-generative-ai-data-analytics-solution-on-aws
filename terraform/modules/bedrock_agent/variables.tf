# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0



variable "additional_policies" {
  type        = list(string)
  description = "List of IAM policy ARNs to attach to the agent role"
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

variable "kms_key_arn" {
  type        = string
  description = "The KMS key ARN to use for the agent."
}
