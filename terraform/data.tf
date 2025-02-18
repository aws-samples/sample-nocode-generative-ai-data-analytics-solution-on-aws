# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

data "aws_caller_identity" "current" {}

data "aws_ec2_managed_prefix_list" "gateway_endpoints" {
  for_each = local.vpce_gateway_services

  name = "com.amazonaws.${var.region}.${each.key}"
}

data "aws_iam_role" "s3_access_roles" {
  count = length(var.s3_access_allowed_roles)
  name  = var.s3_access_allowed_roles[count.index]
}

locals {
  kms_logs_policy = {
    sid    = "Enable Services to Encrypt and Decrypt Payloads"
    effect = "Allow"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]
    principals = [{
      identifiers = ["logs.${var.region}.amazonaws.com"]
      type        = "Service"
    }]
    resources = ["*"]
  }
}
