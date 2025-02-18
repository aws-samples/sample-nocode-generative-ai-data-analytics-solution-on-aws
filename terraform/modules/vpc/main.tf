# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

locals {
  vpc_cidr = var.create_vpc ? "10.0.0.0/16" : data.aws_vpc.vpc[0].cidr_block

  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  vpc_id             = var.create_vpc ? module.vpc[0].vpc_id : var.vpc_config.vpc_id
  public_subnet_ids  = var.create_vpc ? module.vpc[0].public_subnets : var.vpc_config.public_subnet_ids
  private_subnet_ids = var.create_vpc ? module.vpc[0].private_subnets : var.vpc_config.private_subnet_ids

  public_subnets_cidr_blocks  = var.create_vpc ? module.vpc[0].public_subnets_cidr_blocks : data.aws_subnet.public_subnets[*].cidr_block
  private_subnets_cidr_blocks = var.create_vpc ? module.vpc[0].private_subnets_cidr_blocks : data.aws_subnet.private_subnets[*].cidr_block

  public_route_table_ids  = var.create_vpc ? module.vpc[0].public_route_table_ids : data.aws_route_table.public_route_tables[*].route_table_id
  private_route_table_ids = var.create_vpc ? module.vpc[0].private_route_table_ids : data.aws_route_table.private_route_tables[*].route_table_id
}

################################################################################
# VPC
################################################################################
module "vpc" {
  count   = var.create_vpc ? 1 : 0
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

  name = "vpc-code-interpreter"
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 4)]

  enable_nat_gateway     = true
  one_nat_gateway_per_az = true
}
