# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

variable "layer_name" {
  description = "The name of the layer to be created."
  type        = string
}

variable "path_to_layer_build" {
  description = "The absolute path to the shell script that defines the steps to install the packages. Note this has to be a shell script that takes a single argument `layer_zip` which defines the name of the zip file being saved."
  type        = string
}

variable "requirements_file" {
  description = "The path to the requirements.txt file."
  type        = string
}

variable "compatible_runtimes" {
  description = "A list of the compatible runtimes (Default python3.12)."
  type        = list(string)
  default     = ["python3.12"]
}

variable "lambda_layer_zipfile_name" {
  description = "The name of the zip file of the lambda layer."
  type        = string
  default     = null
}

variable "install_location" {
  description = "The name of the zip file of the lambda layer."
  type        = string
  default     = null
}

variable "python_folders" {
  description = "Paths of additional folders to include in the layer."
  type        = list(string)
  default     = []
}
