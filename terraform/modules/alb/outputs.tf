# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

output "target_groups" {
  value = {
    s3          = aws_lb_target_group.s3
    execute_api = aws_lb_target_group.execute_api
    streamlit   = aws_lb_target_group.streamlit
  }
}

output "demo_user" {
  value = {
    username = aws_cognito_user.demo.username
    password = aws_cognito_user.demo.password
  }
}
