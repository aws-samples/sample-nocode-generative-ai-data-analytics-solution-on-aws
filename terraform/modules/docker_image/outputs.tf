# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

output "image_uri" {
  value = data.aws_ecr_image.lambda_image.image_uri
}
