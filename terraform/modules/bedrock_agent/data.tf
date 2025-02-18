# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

data "aws_caller_identity" "current" {}

data "aws_bedrock_inference_profile" "this" {
  count                = var.bedrock_inference_profile != null ? 1 : 0
  inference_profile_id = var.bedrock_inference_profile
}
