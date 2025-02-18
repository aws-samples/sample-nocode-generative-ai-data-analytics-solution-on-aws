# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

data "aws_vpc_endpoint_service" "endpoint_service" {
  service      = var.service
  service_type = var.endpoint_type
}

resource "aws_vpc_endpoint" "endpoint" {
  private_dns_enabled = var.endpoint_type == "Interface" && var.service != "S3" # only enable DNS for interface endpoints
  service_name        = data.aws_vpc_endpoint_service.endpoint_service.service_name
  vpc_id              = var.vpc_id
  security_group_ids  = var.endpoint_type == "Interface" ? var.security_group_ids : null
  subnet_ids          = var.endpoint_type == "Interface" ? var.subnet_ids : null
  vpc_endpoint_type   = var.endpoint_type
  route_table_ids     = var.endpoint_type == "Interface" ? [] : var.route_table_ids
  tags = {
    "Name" = "code-interpreter-${var.service}${var.endpoint_type == "Interface" ? "" : "-gateway"}"
  }
}


data "aws_network_interface" "vpce_enis" {
  count = var.endpoint_type == "Interface" ? length(var.subnet_ids) : 0
  id    = flatten(aws_vpc_endpoint.endpoint.network_interface_ids)[count.index]
}
