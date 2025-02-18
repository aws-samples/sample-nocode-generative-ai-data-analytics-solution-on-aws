# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

data "aws_acm_certificate" "cert" {
  domain      = var.domain_name
  statuses    = ["ISSUED"]
  most_recent = true
}
