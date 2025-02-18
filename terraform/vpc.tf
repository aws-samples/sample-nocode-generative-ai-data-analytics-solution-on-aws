# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

locals {
  vpce_services = toset([
    "s3",
    "execute-api",
    "lambda",
    "sts",
    "bedrock-runtime",
    "logs",
    "ecr.api",
    "ecr.dkr",
  ])

  vpce_gateway_services = toset([
    "s3",
    "dynamodb",
  ])
}

module "vpc" {
  source = "./modules/vpc"

  create_vpc = var.create_vpc
  vpc_config = var.vpc_config
}


module "sg_vpce" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.2"

  name   = "vpce-internal"
  vpc_id = module.vpc.vpc_id

  ingress_rules       = ["https-443-tcp"]
  ingress_cidr_blocks = [module.vpc.cidr_block]

  # for SSM etc
  #egress_rules       = ["https-443-tcp"]
  #egress_cidr_blocks = [module.vpc.cidr_block]
}

module "vpce" {
  for_each = local.vpce_services
  source   = "./modules/vpce"

  service            = each.key
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnets.ids
  security_group_ids = [module.sg_vpce.security_group_id]
  endpoint_type      = "Interface"

  depends_on = [module.vpce_gateway]
}

module "vpce_gateway" {
  for_each = toset(local.vpce_gateway_services)
  source   = "./modules/vpce"

  service         = each.key
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets.ids
  route_table_ids = module.vpc.private_subnets.route_table_ids
  endpoint_type   = "Gateway"
}
