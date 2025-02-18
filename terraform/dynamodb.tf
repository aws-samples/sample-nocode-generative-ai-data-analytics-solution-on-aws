# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

locals {
  dynamodb_ttl_attribute = "ttl"

  sessions_table_name = "code-interpreter-sessions"
  messages_table_name = "code-interpreter-messages"
}

module "kms_dynamodb" {
  source  = "terraform-aws-modules/kms/aws"
  version = "3.0.0"

  description = "DynamoDB key"
  aliases     = ["dynamodb"]
}

################################################################################
# Sessions DynamoDB table
################################################################################
module "dynamodb_sessions" {
  source  = "terraform-aws-modules/dynamodb-table/aws"
  version = "4.0.1"

  name      = local.sessions_table_name
  hash_key  = "user_id"
  range_key = "session_id"

  attributes = [
    {
      name = "user_id"
      type = "S"
    },
    {
      name = "session_id"
      type = "S"
    }
  ]

  server_side_encryption_enabled     = true
  server_side_encryption_kms_key_arn = module.kms_dynamodb.key_arn

  stream_enabled   = true
  stream_view_type = "OLD_IMAGE"
}

################################################################################
# Messages DynamoDB table
################################################################################
module "dynamodb_messages" {
  source  = "terraform-aws-modules/dynamodb-table/aws"
  version = "4.0.1"

  name = local.messages_table_name

  hash_key  = "session_id"
  range_key = "timestamp"

  attributes = [
    {
      name = "session_id"
      type = "S"
    },
    {
      name = "timestamp",
      type = "N"
    }
  ]

  server_side_encryption_enabled     = true
  server_side_encryption_kms_key_arn = module.kms_dynamodb.key_arn
}
