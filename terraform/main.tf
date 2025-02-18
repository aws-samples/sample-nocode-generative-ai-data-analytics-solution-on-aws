# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

locals {
  src_path = abspath("${path.module}/../src")

  central_dynamodb_arns = [
    module.dynamodb_sessions.dynamodb_table_arn,
    module.dynamodb_sessions.dynamodb_table_stream_arn,
    module.dynamodb_messages.dynamodb_table_arn,
  ]

  central_s3_arns = [
    module.s3.bucket_arn,
  ]

  central_kms_arns = [
    module.s3.kms_key_arn,
    module.kms_dynamodb.key_arn,
    module.kms_global.key_arn
  ]
}

### GLOBAL KMS KEY
module "kms_global" {
  source  = "terraform-aws-modules/kms/aws"
  version = "3.0.0"

  description    = "Code Interpreter Global Key"
  aliases        = ["code-interpreter-global"]
  key_statements = [local.kms_logs_policy]
}

module "bedrock_agent" {
  source = "./modules/bedrock_agent"

  bedrock_inference_profile = var.bedrock_inference_profile
  bedrock_model_arn         = var.bedrock_model_arn
  kms_key_arn               = module.kms_global.key_arn

  additional_policies = [
    aws_iam_policy.template["central_s3"].arn,
    aws_iam_policy.template["central_kms"].arn,
  ]
}

### S3 SESSION FILE STORAE
module "s3" {
  source = "./modules/s3"

  bucket_name = var.domain_name
  s3_vpce_id  = module.vpce["s3"].id
  s3_access_allowed_roles = concat(data.aws_iam_role.s3_access_roles[*].arn, [
    module.lambda_api_function.lambda_role_arn,
    module.lambda_agent_service_function.lambda_role_arn,
    aws_iam_role.code_execution_temp_role.arn,
  ])
}

### ALB
module "alb" {
  source = "./modules/alb"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets.ids

  s3_vpce_id                 = module.vpce["s3"].id
  s3_vpce_nr_ips             = length(module.vpc.private_subnets.ids)
  execute_api_vpce_id        = module.vpce["execute-api"].id
  execute_api_vpce_nr_ips    = length(module.vpc.private_subnets.ids)
  private_subnet_cidr_blocks = module.vpc.private_subnets.cidr_blocks
  domain_name                = var.domain_name
  hosted_zone_id             = var.hosted_zone_id
  log_bucket_name            = module.s3.log_bucket_name
  logs_kms_key_arn           = module.kms_global.key_arn
}

### Streamlit UI
module "streamlit" {
  source = "./modules/streamlit"

  region               = var.region
  ecs_kms_key_arn      = module.kms_global.key_arn
  subnet_ids           = module.vpc.private_subnets.ids
  api_base_path        = "${module.api_gateway.api_gateway_invoke_url}/api/"
  alb_target_group_arn = module.alb.target_groups["streamlit"].arn
  streamlit_src_path   = "${path.root}/../ui/"
  vpc_id               = module.vpc.vpc_id
}


### API Gateway
module "api_gateway" {
  source = "./modules/api_gateway"

  domain_name         = var.domain_name
  execute_api_vpce_id = module.vpce["execute-api"].id
  rest_api_spec = templatefile("./resources/open_api_spec.tmpl", {
    api_lambda_rest_api_invoke_arn = module.lambda_api_function.lambda_function_invoke_arn
  })
  logs_kms_key_arn = module.kms_global.key_arn
}


### SQS DLQ
module "sqs_dlq" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.2.0"

  name = "code-interpreter-dlq"

  kms_master_key_id                 = module.kms_global.key_arn
  kms_data_key_reuse_period_seconds = 3600
}
