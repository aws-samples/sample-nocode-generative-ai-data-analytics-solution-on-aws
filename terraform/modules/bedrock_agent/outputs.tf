# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

output "agent_id" {
  value = aws_bedrockagent_agent.agent.agent_id
}

output "agent_alias" {
  value = aws_bedrockagent_agent_alias.alias.agent_alias_id
}
