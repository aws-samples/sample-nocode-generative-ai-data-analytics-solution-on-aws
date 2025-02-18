// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

region                    = "aa-example-1"
domain_name               = "code-interpreter.example.com"
s3_access_allowed_roles   = ["admin"]
hosted_zone_id            = "Z01234567890123456789"
bedrock_inference_profile = "us.amazon.nova-pro-v1:0"

create_vpc = true
# vpc_config = {
#   vpc_id             = "vpc-01234567890123451"
#   public_subnet_ids  = ["subnet-01234567890123451", "subnet-01234567890123452"]
#   private_subnet_ids = ["subnet-01234567890123453"]
#}
