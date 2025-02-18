# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

locals {
  bedrock_model_resources = var.bedrock_inference_profile != null ? concat(
    data.aws_bedrock_inference_profile.this[0].models[*].model_arn,
    [data.aws_bedrock_inference_profile.this[0].inference_profile_arn]
  ) : [var.bedrock_model_arn]
}

################################################################################
# IAM
################################################################################
data "aws_iam_policy_document" "agent_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["bedrock.amazonaws.com"]
      type        = "Service"
    }
    condition {
      test     = "StringEquals"
      values   = [data.aws_caller_identity.current.account_id]
      variable = "aws:SourceAccount"
    }
    condition {
      test     = "ArnLike"
      values   = ["arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:agent/*"]
      variable = "AWS:SourceArn"
    }
  }
}

data "aws_iam_policy_document" "agent_permissions" {
  statement {
    actions = [
      "bedrock:InvokeModel*",
      "bedrock:GetInferenceProfile",
    ]
    resources = local.bedrock_model_resources
  }
  statement {
    actions = [
      "bedrock:ApplyGuardrail",
    ]
    resources = [aws_bedrock_guardrail.guardrail.guardrail_arn]
  }
}

resource "aws_iam_role" "agent_role" {
  assume_role_policy = data.aws_iam_policy_document.agent_trust.json
  name_prefix        = "AmazonBedrockExecutionRoleForAgents_"
}

resource "aws_iam_role_policy" "agent_policy" {
  policy = data.aws_iam_policy_document.agent_permissions.json
  role   = aws_iam_role.agent_role.id
}

resource "aws_iam_role_policy_attachment" "name" {
  count      = length(var.additional_policies)
  policy_arn = var.additional_policies[count.index]
  role       = aws_iam_role.agent_role.id
}

################################################################################
# Bedrock Agent
################################################################################
resource "aws_bedrockagent_agent" "agent" {
  agent_name                  = "code-interpreter-agent"
  agent_resource_role_arn     = aws_iam_role.agent_role.arn
  idle_session_ttl_in_seconds = 60
  foundation_model            = var.bedrock_inference_profile != null ? data.aws_bedrock_inference_profile.this[0].inference_profile_arn : var.bedrock_model_arn
  instruction                 = file("${path.module}/resources/agent_instruction.txt")
  customer_encryption_key_arn = var.kms_key_arn
  guardrail_configuration = [{
    guardrail_identifier = aws_bedrock_guardrail.guardrail.guardrail_id
    guardrail_version    = aws_bedrock_guardrail.guardrail.version
  }]

  depends_on = [aws_iam_role_policy.agent_policy]

  lifecycle {
    precondition {
      condition     = (var.bedrock_inference_profile != null && var.bedrock_model_arn == null) || (var.bedrock_inference_profile == null && var.bedrock_model_arn != null)
      error_message = "Either bedrock_inference_profile or bedrock_model_id needs to be defined."
    }
  }
}

resource "aws_bedrockagent_agent_alias" "alias" {
  agent_alias_name = "main"
  agent_id         = aws_bedrockagent_agent.agent.id
  lifecycle { # this should create a new version
    replace_triggered_by = [
      aws_bedrockagent_agent.agent.agent.foundation_model,
      aws_bedrockagent_agent.agent.agent.instruction,
      aws_bedrockagent_agent.agent.agent.idle_session_ttl_in_seconds,
      aws_bedrockagent_agent_action_group.python_tool
    ]
  }
}

resource "aws_bedrockagent_agent_action_group" "python_tool" {
  action_group_name          = "python_tool"
  agent_id                   = aws_bedrockagent_agent.agent.id
  agent_version              = "DRAFT" #aws_bedrockagent_agent.agent.agent_version
  skip_resource_in_use_check = true
  action_group_executor {
    custom_control = "RETURN_CONTROL"
  }
  function_schema {
    member_functions {
      functions {
        name        = "python_repl"
        description = "Use this tool to execute python code. You will be able to read anything that you print out to stdout using print(...). Errors will be returned to you."
        parameters {
          map_block_key = "python_code"
          type          = "string"
          description   = "The Python code to execute."
          required      = true
        }
      }
    }
  }
}

resource "aws_bedrock_guardrail" "guardrail" {
  name                      = "agent-guardrail"
  blocked_input_messaging   = "Your input was blocked."
  blocked_outputs_messaging = "Agent output was blocked."
  description               = "Code Interpreter Agent Guardrail"

  content_policy_config {
    dynamic "filters_config" {
      for_each = toset(["SEXUAL", "VIOLENCE", "HATE", "INSULTS", "MISCONDUCT", "PROMPT_ATTACK"])
      content {
        input_strength  = "MEDIUM"
        output_strength = filters_config.value == "PROMPT_ATTACK" ? "NONE" : "MEDIUM"
        type            = filters_config.value
      }
    }
  }
}
