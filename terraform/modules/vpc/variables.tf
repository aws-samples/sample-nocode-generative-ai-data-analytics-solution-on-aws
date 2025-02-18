# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

variable "create_vpc" {
  type        = bool
  default     = false
  description = "Whether to deploy a example VPC."
}

variable "vpc_config" {
  type = object({
    vpc_id             = string
    public_subnet_ids  = list(string)
    private_subnet_ids = list(string)
  })
  default     = null
  description = "VPC configuration object"
}
