# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

output "vpc_id" {
  value = local.vpc_id
}

output "cidr_block" {
  value = local.vpc_cidr
}

output "public_subnets" {
  value = {
    ids             = local.public_subnet_ids
    cidr_blocks     = local.public_subnets_cidr_blocks
    route_table_ids = local.public_route_table_ids
  }
}

output "private_subnets" {
  value = {
    ids             = local.private_subnet_ids
    cidr_blocks     = local.private_subnets_cidr_blocks
    route_table_ids = local.private_route_table_ids
  }
}
