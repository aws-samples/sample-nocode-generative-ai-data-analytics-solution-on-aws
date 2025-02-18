# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

################################################################################
# Reusable policy templates
################################################################################
locals {
  template_policies = {
    central_s3                   = { type = "s3", resources = flatten([for x in local.central_s3_arns : [x, "${x}/*"]]) }
    central_kms                  = { type = "kms", resources = local.central_kms_arns }
    central_dynamodb             = { type = "dynamodb", resources = local.central_dynamodb_arns }
    bedrock                      = { type = "bedrock", resources = [] }
    sqs                          = { type = "sqs", resources = [module.sqs_dlq.queue_arn] }
    invoke_lambda_agent_service  = { type = "lambda", resources = [module.lambda_agent_service_function.lambda_function_arn_static] }
    invoke_lambda_code_execution = { type = "lambda", resources = [module.lambda_code_execution_function.lambda_function_arn_static] }
  }
}

resource "aws_iam_policy" "template" {
  for_each    = local.template_policies
  name_prefix = "policy-${each.key}-"
  policy = templatefile("./resources/policies/template_${each.value["type"]}_policy.tmpl", {
    resource_arns = jsonencode(each.value["resources"])
    region        = var.region
    account_id    = data.aws_caller_identity.current.account_id
  })
}

################################################################################
# Code Execution Lambda role and policy
################################################################################
data "aws_iam_policy_document" "code_execution_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [module.lambda_agent_service_function.lambda_role_arn]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "code_execution_temp_role" {
  name               = "lambda-code-execution-temp-role"
  assume_role_policy = data.aws_iam_policy_document.code_execution_assume_role.json
}

resource "aws_iam_policy" "code_execution_temp_role_s3_policy" {
  name        = "code-execution-s3-access"
  description = "Inline policy for s3 access"
  policy = templatefile("./resources/policies/code_execution_temp_role_policy.tmpl", {
    s3_bucket_arn = module.s3.bucket_arn,
    kms_key_arn   = module.s3.kms_key_arn
  })
}

resource "aws_iam_role_policy_attachment" "attachment_code_execution_temp_role" {
  role       = aws_iam_role.code_execution_temp_role.name
  policy_arn = aws_iam_policy.code_execution_temp_role_s3_policy.arn
}
