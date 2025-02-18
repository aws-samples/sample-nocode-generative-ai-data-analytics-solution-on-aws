# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

output "execution_arn" {
  value = aws_api_gateway_rest_api.api.execution_arn
}

output "api_gateway_invoke_url" {
  value = aws_api_gateway_stage.default.invoke_url
}
