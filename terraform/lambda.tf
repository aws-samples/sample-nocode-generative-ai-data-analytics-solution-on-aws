# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

locals {
  global_lambda_environment_variables = merge(var.lambda_environment_variables, {
    S3_FILE_STORAGE_BUCKET_NAME = module.s3.bucket_name
    DDB_SESSIONS_TABLE_NAME     = local.sessions_table_name
    DDB_MESSAGES_TABLE_NAME     = local.messages_table_name
    DDB_TTL_ATTRIBUTE           = local.dynamodb_ttl_attribute
  })

  api_lambda_environment_variables = merge(local.global_lambda_environment_variables, {
    LAMBDA_AGENT_SERVICE_FUNCTION_NAME = module.lambda_agent_service_function.lambda_function_arn
  })

  agent_service_lambda_environment_variables = merge(local.global_lambda_environment_variables, {
    LAMBDA_CODE_EXECUTION_FUNCTION_NAME = module.lambda_code_execution_function.lambda_function_arn
    BEDROCK_AWS_REGION                  = "us-east-1" #var.region
    BEDROCK_AGENT_ID                    = module.bedrock_agent.agent_id
    BEDROCK_AGENT_ALIAS                 = module.bedrock_agent.agent_alias
    S3_FILE_STORAGE_BUCKET_KMS_KEY_ARN  = module.s3.kms_key_arn
    IAM_TEMPORARY_ROLE_ARN              = aws_iam_role.code_execution_temp_role.arn
  })

  code_execution_lambda_environment_variables = merge(var.lambda_environment_variables, {
    S3_FILE_STORAGE_BUCKET_NAME = module.s3.bucket_name
  })

  session_maintenance_lambda_environment_variables = merge(local.global_lambda_environment_variables, {
  })
}

################################################################################
# KMS and Security Groups
################################################################################
module "kms_lambda" {
  source  = "terraform-aws-modules/kms/aws"
  version = "3.0.0"

  description    = "Lambda key"
  aliases        = ["lambda"]
  key_statements = [local.kms_logs_policy]
}

module "sg_lambda" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.2"

  name   = "lambda-internal"
  vpc_id = module.vpc.vpc_id

  egress_rules            = ["https-443-tcp"]
  egress_cidr_blocks      = module.vpc.private_subnets.cidr_blocks
  egress_ipv6_cidr_blocks = []
  egress_prefix_list_ids  = values(data.aws_ec2_managed_prefix_list.gateway_endpoints)[*].id
}

module "sg_lambda_code_execution" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.2"

  name   = "lambda-code-execution-s3"
  vpc_id = module.vpc.vpc_id

  egress_rules            = ["https-443-tcp"]
  egress_cidr_blocks      = []
  egress_ipv6_cidr_blocks = []
  egress_prefix_list_ids  = [data.aws_ec2_managed_prefix_list.gateway_endpoints["s3"].id]
}

################################################################################
# Lambda Layer
################################################################################
module "code_interpreter_base_lambda_layer" {
  source = "./modules/lambda_layer"

  layer_name          = "code-interpreter-base-layer"
  path_to_layer_build = "${local.src_path}/lambda_layer/build_layer.sh"
  requirements_file   = abspath("${local.src_path}/lambda_layer/requirements.txt")
  python_folders      = [abspath("${local.src_path}/lambda_layer/codeinterpreter_lib")]
}

################################################################################
# API Lambda function
################################################################################
module "lambda_api_function" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "7.4.0"

  function_name = "code-interpreter-api"
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  memory_size   = 512
  timeout       = 29
  tracing_mode  = "Active"
  architectures = ["arm64"]

  source_path = "${local.src_path}/lambda_functions/api/src"

  environment_variables = local.api_lambda_environment_variables

  layers = [module.code_interpreter_base_lambda_layer.arn]

  kms_key_arn                       = module.kms_lambda.key_arn
  cloudwatch_logs_kms_key_id        = module.kms_lambda.key_arn
  cloudwatch_logs_retention_in_days = 30

  vpc_subnet_ids         = module.vpc.private_subnets.ids
  vpc_security_group_ids = [module.sg_lambda.security_group_id]
  attach_network_policy  = true
  attach_tracing_policy  = true

  allowed_triggers = {
    APIGatewayAny = {
      service    = "apigateway"
      source_arn = "${module.api_gateway.execution_arn}/*"
    },
  }
  create_current_version_allowed_triggers = false

  attach_policies    = true
  number_of_policies = 4
  policies = [
    aws_iam_policy.template["central_s3"].arn,
    aws_iam_policy.template["central_dynamodb"].arn,
    aws_iam_policy.template["central_kms"].arn,
    aws_iam_policy.template["invoke_lambda_agent_service"].arn,
  ]
}

################################################################################
# Agent service Lambda function
################################################################################
module "lambda_agent_service_function" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "7.4.0"

  function_name = "code-interpreter-agent-service"
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  memory_size   = 512
  timeout       = 900
  tracing_mode  = "Active"
  architectures = ["arm64"]

  source_path = "${local.src_path}/lambda_functions/agent_service/src"

  environment_variables = local.agent_service_lambda_environment_variables

  layers = [module.code_interpreter_base_lambda_layer.arn]

  kms_key_arn                       = module.kms_lambda.key_arn
  cloudwatch_logs_kms_key_id        = module.kms_lambda.key_arn
  cloudwatch_logs_retention_in_days = 30

  #vpc_subnet_ids         = module.vpc.private_subnets.ids
  #vpc_security_group_ids = [module.sg_lambda.security_group_id]
  #attach_network_policy  = true
  attach_tracing_policy = true

  attach_policies    = true
  number_of_policies = 5
  policies = [
    aws_iam_policy.template["central_s3"].arn,
    aws_iam_policy.template["central_dynamodb"].arn,
    aws_iam_policy.template["central_kms"].arn,
    aws_iam_policy.template["bedrock"].arn,
    aws_iam_policy.template["invoke_lambda_code_execution"].arn,
  ]
}

################################################################################
# Session maintenance Lambda function
################################################################################
module "lambda_session_maintenance_function" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "7.4.0"

  function_name = "code-interpreter-session-maintenance"
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  memory_size   = 128
  timeout       = 900
  tracing_mode  = "Active"
  architectures = ["arm64"]

  source_path = "${local.src_path}/lambda_functions/session_maintenance/src"

  environment_variables = local.session_maintenance_lambda_environment_variables

  layers = [module.code_interpreter_base_lambda_layer.arn]

  kms_key_arn                       = module.kms_lambda.key_arn
  cloudwatch_logs_kms_key_id        = module.kms_lambda.key_arn
  cloudwatch_logs_retention_in_days = 30

  vpc_subnet_ids         = module.vpc.private_subnets.ids
  vpc_security_group_ids = [module.sg_lambda.security_group_id]
  attach_network_policy  = true
  attach_tracing_policy  = true

  event_source_mapping = {
    dynamodb = {
      event_source_arn                   = module.dynamodb_sessions.dynamodb_table_stream_arn
      destination_arn_on_failure         = module.sqs_dlq.queue_arn
      starting_position                  = "LATEST"
      batch_size                         = 10
      maximum_batching_window_in_seconds = 10
      maximum_retry_attempts             = 3
      filter_criteria                    = [{ pattern = jsonencode({ eventName : ["REMOVE"] }) }, ]
    }
  }

  attach_policies    = true
  number_of_policies = 4
  policies = [
    aws_iam_policy.template["central_s3"].arn,
    aws_iam_policy.template["central_dynamodb"].arn,
    aws_iam_policy.template["central_kms"].arn,
    aws_iam_policy.template["sqs"].arn,
  ]
}

################################################################################
# Code execution Lambda function
################################################################################

## Docker image
module "code_execution_docker_image" {
  source = "./modules/docker_image"

  name               = "code-interpreter-code-execution"
  region             = var.region
  ecr_kms_key_arn    = module.kms_lambda.key_arn
  build_context_path = local.src_path
  dockerfile_path    = "${local.src_path}/lambda_functions/code_execution/Dockerfile"
}

module "lambda_code_execution_function" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "7.4.0"

  function_name = "code-interpreter-code-execution"
  memory_size   = 2048
  timeout       = 300
  tracing_mode  = "Active"

  create_package = false
  package_type   = "Image"
  architectures  = ["arm64"] # ["x86_64"]

  image_uri = module.code_execution_docker_image.image_uri

  environment_variables = local.code_execution_lambda_environment_variables

  kms_key_arn                       = module.kms_lambda.key_arn
  cloudwatch_logs_kms_key_id        = module.kms_lambda.key_arn
  cloudwatch_logs_retention_in_days = 30

  vpc_subnet_ids         = module.vpc.private_subnets.ids
  vpc_security_group_ids = [module.sg_lambda_code_execution.security_group_id]
  attach_network_policy  = true
  attach_tracing_policy  = true
}
