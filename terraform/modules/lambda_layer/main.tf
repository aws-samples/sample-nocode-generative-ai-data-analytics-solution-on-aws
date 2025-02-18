# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

locals {
  install_location          = coalesce(var.install_location, "./builds/${var.layer_name}")
  lambda_layer_zipfile_name = coalesce(var.lambda_layer_zipfile_name, "./builds/${var.layer_name}.zip")
}

data "external" "create_lambda_layer_dependencies" {
  program = ["bash", var.path_to_layer_build]
  query = {
    layer_loc         = local.install_location
    python_versions   = join(",", var.compatible_runtimes)
    requirements_file = var.requirements_file
    python_folders    = join(" ", var.python_folders)
  }
}

data "archive_file" "lambda_layer_zip_file" {
  depends_on = [data.external.create_lambda_layer_dependencies]

  output_path = local.lambda_layer_zipfile_name
  source_dir  = "${local.install_location}/"
  type        = "zip"
}

resource "aws_lambda_layer_version" "lambda_layer" {
  compatible_runtimes = var.compatible_runtimes
  filename            = data.archive_file.lambda_layer_zip_file.output_path
  layer_name          = var.layer_name
  source_code_hash    = data.archive_file.lambda_layer_zip_file.output_base64sha256
}
