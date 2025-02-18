# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

data "aws_availability_zones" "available" {}

################################################################################
# VPC data
################################################################################
data "aws_vpc" "vpc" {
  count = var.create_vpc ? 0 : 1
  id    = var.vpc_config.vpc_id

  lifecycle {
    precondition {
      condition = (
        var.create_vpc &&
        var.vpc_config.vpc_id == null &&
        length(var.vpc_config.public_subnet_ids) == 0 &&
        length(var.vpc_config.public_subnet_ids) == 0
        ) || (
        !var.create_vpc &&
        var.vpc_config.vpc_id != null &&
        length(var.vpc_config.private_subnet_ids) != 0 &&
        length(var.vpc_config.private_subnet_ids) != 0
      )
      error_message = "Need to either specify \"create_vpc\" or \"vpc_config\" with all attributes"
    }
  }
}

data "aws_subnet" "public_subnets" {
  count = var.create_vpc ? 0 : length(var.vpc_config.public_subnet_ids)
  id    = var.vpc_config.public_subnet_ids[count.index]
}

data "aws_subnet" "private_subnets" {
  count = var.create_vpc ? 0 : length(var.vpc_config.private_subnet_ids)
  id    = var.vpc_config.private_subnet_ids[count.index]
}

data "aws_route_table" "public_route_tables" {
  count     = var.create_vpc ? 0 : length(var.vpc_config.public_subnet_ids)
  subnet_id = var.vpc_config.public_subnet_ids[count.index]
}

data "aws_route_table" "private_route_tables" {
  count     = var.create_vpc ? 0 : length(var.vpc_config.private_subnet_ids)
  subnet_id = var.vpc_config.private_subnet_ids[count.index]
}
