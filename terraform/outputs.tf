# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

output "api_base_path" {
  value = "https://${var.domain_name}/api/"
}

output "streamlit_url" {
  value = "https://${var.domain_name}"
}

output "demo_user" {
  value     = module.alb.demo_user
  sensitive = true
}
