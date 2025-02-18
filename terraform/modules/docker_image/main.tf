# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

################################################################################
# ECR
################################################################################
resource "aws_ecr_repository" "lambda_image" {
  name                 = var.name
  image_tag_mutability = "IMMUTABLE"

  force_delete = true
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.ecr_kms_key_arn
  }
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "repo_policy" {
  repository = aws_ecr_repository.lambda_image.name
  policy     = file("${path.module}/resources/ecr_lifecycle_policy.tmpl")
}

################################################################################
# Docker image
################################################################################
resource "time_static" "container_update" {
  triggers = { src_hash = sha256(join("", [for f in fileset(var.build_context_path, "**") : filesha256("${var.build_context_path}/${f}")])) }
}

locals {
  image_tag = formatdate("YYYYMMDDhhmmss", time_static.container_update.id) #"latest"
  image_uri = "${aws_ecr_repository.lambda_image.repository_url}:${local.image_tag}"
}

resource "null_resource" "build_and_push_docker_image" {
  provisioner "local-exec" {
    command = <<-EOT
    aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${aws_ecr_repository.lambda_image.repository_url}
    docker build --platform=linux/arm64 -t ${local.image_uri} ${var.dockerfile_path != null ? "--file \"${var.dockerfile_path}\"" : ""} "${var.build_context_path}"
    docker push ${local.image_uri}
    EOT
  }

  triggers = { image_tag = local.image_tag }
}

data "aws_ecr_image" "lambda_image" {
  repository_name = aws_ecr_repository.lambda_image.name
  image_tag       = local.image_tag
  depends_on = [
    null_resource.build_and_push_docker_image
  ]
}
