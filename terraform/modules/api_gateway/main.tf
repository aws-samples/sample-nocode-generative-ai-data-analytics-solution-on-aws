# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

################################################################################
# API Gateway
################################################################################
data "aws_iam_policy_document" "allow_api_gw_via_vpce" {
  #checkov:skip=CKV_AWS_111: "Ensure IAM policies does not allow write access without constraints"
  statement {
    effect = "Allow"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions   = ["execute-api:Invoke"]
    resources = ["*"]
  }
  statement {
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions   = ["execute-api:Invoke"]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:SourceVpce"
      values   = [var.execute_api_vpce_id]
    }
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name = "code-interpreter-rest-api"

  disable_execute_api_endpoint = false
  endpoint_configuration {
    types            = ["PRIVATE"]
    vpc_endpoint_ids = [var.execute_api_vpce_id]
  }

  body = var.rest_api_spec

  policy = data.aws_iam_policy_document.allow_api_gw_via_vpce.json

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_method_settings" "api" {
  #checkov:skip=CKV_AWS_225: Do not use API Gateway caching in this example
  #checkov:skip=CKV_AWS_308: Do not use API Gateway cache encryption in this example
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.default.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled = true
    logging_level   = "ERROR"
  }
}

resource "aws_api_gateway_domain_name" "api" {
  domain_name              = var.domain_name
  regional_certificate_arn = data.aws_acm_certificate.cert.arn
  security_policy          = "TLS_1_2"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_base_path_mapping" "api" {
  api_id      = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.default.stage_name
  domain_name = aws_api_gateway_domain_name.api.domain_name
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  triggers = {
    body = sha1(var.rest_api_spec)
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/apigateway/code-interpreter-rest-api"
  kms_key_id        = var.logs_kms_key_arn
  retention_in_days = 7
}

# nosemgrep: missing-api-gateway-cache-cluster
resource "aws_api_gateway_stage" "default" {
  #checkov:skip=CKV2_AWS_51: Do not use client certificate authentication in this example
  #checkov:skip=CKV_AWS_120: Do not use API Gateway caching in this example
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "default"

  xray_tracing_enabled = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format = jsonencode({
      "requestId" : "$context.requestId",
      "extendedRequestId" : "$context.extendedRequestId",
      "ip" : "$context.identity.sourceIp",
      "caller" : "$context.identity.caller",
      "user" : "$context.identity.user",
      "requestTime" : "$context.requestTime",
      "httpMethod" : "$context.httpMethod",
      "resourcePath" : "$context.resourcePath",
      "status" : "$context.status",
      "protocol" : "$context.protocol",
      "responseLength" : "$context.responseLength"
    })
  }
}

resource "aws_api_gateway_account" "api" {
  cloudwatch_role_arn = aws_iam_role.cloudwatch.arn
}

resource "aws_iam_role" "cloudwatch" {
  name = "api-gateway-cloudwatch-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}
