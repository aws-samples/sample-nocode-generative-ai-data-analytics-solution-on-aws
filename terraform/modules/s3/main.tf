# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

module "kms_s3" {
  source  = "terraform-aws-modules/kms/aws"
  version = "3.0.0"

  description = "S3 key"
  aliases     = ["s3-code-interpreter"]
}

module "private_bucket" {
  #checkov:skip=CKV_AWS_144: No cross-region replication needed in example
  #checkov:skip=CKV2_AWS_62: No event notifications needed in example
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "4.5.0"

  bucket = var.bucket_name

  # Allow deletion of non-empty bucket
  force_destroy = true

  versioning = {
    enabled = true
  }

  logging = {
    target_bucket = module.logging_bucket.s3_bucket_id
    target_prefix = "logs/"
  }

  lifecycle_rule = [
    {
      id                                     = "LifecycleRule"
      enabled                                = true
      abort_incomplete_multipart_upload_days = 1
      noncurrent_version_expiration          = { days = 90 }
    }
  ]

  server_side_encryption_configuration = {
    rule = {
      bucket_key_enabled = true
      apply_server_side_encryption_by_default = {
        kms_master_key_id = module.kms_s3.key_id
        sse_algorithm     = "aws:kms"
      }
    }
  }

  # policies
  attach_policy                         = true
  policy                                = data.aws_iam_policy_document.limit_access.json
  attach_deny_insecure_transport_policy = true
}

data "aws_iam_policy_document" "limit_access" {
  statement {
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]

    resources = [
      module.private_bucket.s3_bucket_arn,
      "${module.private_bucket.s3_bucket_arn}/*",
    ]

    condition {
      test     = "StringNotEquals"
      variable = "aws:SourceVpce"
      values   = [var.s3_vpce_id]
    }

    dynamic "condition" {
      for_each = length(var.s3_access_allowed_roles) > 0 ? [1] : []
      content {
        test     = "ForAllValues:ArnNotEquals"
        variable = "aws:PrincipalARN"
        values   = var.s3_access_allowed_roles
      }
    }

    dynamic "condition" {
      for_each = var.s3_access_allow_aws_services ? [1] : []
      content {
        test     = "BoolIfExists"
        variable = "aws:PrincipalIsAWSService"
        values   = "true"
      }
    }

    dynamic "condition" {
      for_each = length(var.s3_access_allowed_service_principals) > 0 ? [1] : []
      content {
        test     = "ForAllValues:ArnNotEquals"
        variable = "aws:PrincipalServiceName"
        values   = var.s3_access_allowed_service_principals
      }
    }

  }
}


# LOGGING BUCKET
module "logging_bucket" {
  #checkov:skip=CKV_AWS_21: No versioning needed for logging bucket
  #checkov:skip=CKV_AWS_144: No cross-region replication needed in example
  #checkov:skip=CKV2_AWS_62: No event notifications needed in example
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "4.5.0"

  bucket = "${var.bucket_name}-logs"

  # Allow deletion of non-empty bucket
  force_destroy = true

  versioning = {
    enabled = true
  }

  lifecycle_rule = [
    {
      id                                     = "LifecycleRule"
      enabled                                = true
      abort_incomplete_multipart_upload_days = 1
      expiration                             = { days = 30 }
    }
  ]

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256" # no KMS keys supported for logs
      }
    }
  }

  # policies
  attach_policy                         = true
  policy                                = data.aws_iam_policy_document.log_policy_document.json
  attach_deny_insecure_transport_policy = true
}

# AWS Load Balancer access log delivery policy
data "aws_elb_service_account" "this" {}

data "aws_iam_policy_document" "log_policy_document" {
  statement {
    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.this.arn]
    }
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${module.logging_bucket.s3_bucket_arn}/*"]
  }

  statement {
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetBucketAcl"
    ]
    resources = [
      module.logging_bucket.s3_bucket_arn,
      "${module.logging_bucket.s3_bucket_arn}/*",
    ]
  }
}
