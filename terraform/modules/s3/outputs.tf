# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

output "bucket_name" {
  value = module.private_bucket.s3_bucket_id
}

output "bucket_arn" {
  value = module.private_bucket.s3_bucket_arn
}

output "kms_key_arn" {
  value = module.kms_s3.key_arn
}


output "log_bucket_name" {
  value = module.logging_bucket.s3_bucket_id
}

output "log_bucket_arn" {
  value = module.logging_bucket.s3_bucket_arn
}
