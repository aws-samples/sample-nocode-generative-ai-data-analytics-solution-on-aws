# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

################################################################################
# Cognito
################################################################################
resource "aws_cognito_user_pool" "pool" {
  name = "code-interpreter-demo"
  admin_create_user_config {
    allow_admin_create_user_only = true
  }
}

resource "aws_cognito_user_pool_domain" "domain" {
  domain       = "${aws_cognito_user_pool.pool.name}-domain"
  user_pool_id = aws_cognito_user_pool.pool.id
}

resource "aws_cognito_user_pool_client" "client" {
  name                                 = "${aws_cognito_user_pool_domain.domain.domain}-client"
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid"]
  callback_urls                        = ["https://${var.domain_name}/oauth2/idpresponse"]
  generate_secret                      = true
  supported_identity_providers         = ["COGNITO"]
  user_pool_id                         = aws_cognito_user_pool.pool.id
}

resource "random_password" "password" {
  length = 16
}

resource "aws_cognito_user" "demo" {
  user_pool_id = aws_cognito_user_pool.pool.id
  username     = "demo"
  password     = random_password.password.result
}
