# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

################################################################################
# Security Group
################################################################################
module "sg_alb" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.2"

  name   = "alb"
  vpc_id = var.vpc_id

  ingress_rules       = ["https-443-tcp", "http-80-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]

  egress_with_cidr_blocks = [
    {
      rule        = "https-443-tcp"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      from_port   = 8501
      to_port     = 8501
      protocol    = "tcp"
      description = "Streamlit UI"
      cidr_blocks = join(",", var.private_subnet_cidr_blocks)
    }
  ]
}

##################################################################################
# WAF
##################################################################################
resource "aws_wafv2_web_acl" "web_acl" {
  name  = "code-interpreter-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        rule_action_override {
          action_to_use {
            count {}
          }

          name = "SizeRestrictions_BODY"
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWS-AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "WAF-metric-code-interpreter"
    sampled_requests_enabled   = true
  }
}



resource "aws_cloudwatch_log_group" "waf_log_group" {
  name              = "aws-waf-logs-code-interpreter"
  retention_in_days = 7
  kms_key_id        = var.logs_kms_key_arn
}


resource "aws_wafv2_web_acl_logging_configuration" "web_acl" {
  resource_arn            = aws_wafv2_web_acl.web_acl.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf_log_group.arn]
}

resource "aws_wafv2_web_acl_association" "association" {
  resource_arn = aws_lb.alb.arn
  web_acl_arn  = aws_wafv2_web_acl.web_acl.arn
}

##################################################################################
# Target Groups
##################################################################################

# S3
resource "aws_lb_target_group" "s3" {
  name        = "alb-s3-target-group"
  target_type = "ip"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = var.vpc_id

  health_check {
    matcher  = "200,307,403"
    protocol = "HTTPS"
    path     = "/"
    interval = 30
    timeout  = 10
  }
}

data "aws_vpc_endpoint" "s3_vpce" {
  id = var.s3_vpce_id
}

data "aws_network_interface" "s3_vpce_enis" {
  count = var.s3_vpce_nr_ips
  id    = flatten(data.aws_vpc_endpoint.s3_vpce.network_interface_ids)[count.index]
}

resource "aws_lb_target_group_attachment" "s3" {
  count            = var.s3_vpce_nr_ips
  target_group_arn = aws_lb_target_group.s3.arn
  target_id        = flatten(data.aws_network_interface.s3_vpce_enis[*].private_ips)[count.index]
}

# Execute API
resource "aws_lb_target_group" "execute_api" {
  name        = "alb-execute-api-target-group"
  target_type = "ip"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = var.vpc_id

  health_check {
    matcher  = "200,403"
    protocol = "HTTPS"
    path     = "/"
    interval = 30
    timeout  = 10
  }
}

data "aws_vpc_endpoint" "execute_api_vpce" {
  id = var.execute_api_vpce_id
}

data "aws_network_interface" "execute_api_vpce_enis" {
  count = var.execute_api_vpce_nr_ips
  id    = flatten(data.aws_vpc_endpoint.execute_api_vpce.network_interface_ids)[count.index]
}

resource "aws_lb_target_group_attachment" "execute_api" {
  count            = var.execute_api_vpce_nr_ips
  target_group_arn = aws_lb_target_group.execute_api.arn
  target_id        = flatten(data.aws_network_interface.execute_api_vpce_enis[*].private_ips)[count.index]
}

# Streamlit
resource "aws_lb_target_group" "streamlit" {
  name        = "alb-streamlit-target-group"
  target_type = "ip"
  port        = 8501
  protocol    = "HTTP"
  vpc_id      = var.vpc_id

  health_check {
    matcher  = "200"
    protocol = "HTTP"
    path     = "/_stcore/health"
    interval = 30
    timeout  = 10
  }
}


##################################################################################
# Application Load Balancer
##################################################################################
# nosemgrep: missing-aws-lb-deletion-protection
resource "aws_lb" "alb" {
  #checkov:skip=CKV_AWS_150: Do not enable deletion protection for example
  name = "alb-code-interpreter"

  load_balancer_type         = "application"
  subnets                    = var.subnet_ids
  security_groups            = [module.sg_alb.security_group_id]
  internal                   = false
  enable_deletion_protection = false
  drop_invalid_header_fields = true

  access_logs {
    enabled = true
    bucket  = var.log_bucket_name
    prefix  = "alb/access"

  }

  connection_logs {
    enabled = true
    bucket  = var.log_bucket_name
    prefix  = "alb/connection"
  }
}

# HTTPS listener (default)
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  certificate_arn = data.aws_acm_certificate.cert.arn

  default_action {
    type  = "authenticate-cognito"
    order = 1

    authenticate_cognito {
      scope               = "openid"
      user_pool_arn       = aws_cognito_user_pool.pool.arn
      user_pool_client_id = aws_cognito_user_pool_client.client.id
      user_pool_domain    = aws_cognito_user_pool_domain.domain.domain
    }
  }

  default_action {
    type  = "forward"
    order = 50000

    target_group_arn = aws_lb_target_group.streamlit.arn
  }
}

# HTTP listener (redirect to HTTPS)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

################################################################################
# ALB rules
################################################################################
# API rule
resource "aws_lb_listener_rule" "api_rule" {
  listener_arn = aws_lb_listener.https.arn

  priority = 2

  action {
    type  = "authenticate-cognito"
    order = 1

    authenticate_cognito {
      scope               = "openid"
      user_pool_arn       = aws_cognito_user_pool.pool.arn
      user_pool_client_id = aws_cognito_user_pool_client.client.id
      user_pool_domain    = aws_cognito_user_pool_domain.domain.domain
    }
  }

  action {
    order            = 50000
    type             = "forward"
    target_group_arn = aws_lb_target_group.execute_api.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}

# S3 rule
resource "aws_lb_listener_rule" "s3_post_rule" {
  listener_arn = aws_lb_listener.https.arn

  priority = 3

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.s3.arn
  }

  condition {
    path_pattern {
      values = ["/"]
    }
  }
  condition {
    http_request_method {
      values = ["POST"]
    }
  }
}

resource "aws_lb_listener_rule" "s3_rule" {
  listener_arn = aws_lb_listener.https.arn

  priority = 4

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.s3.arn
  }

  condition {
    path_pattern {
      values = ["/sessions/*"]
    }
  }
}


################################################################################
# Route53 record
################################################################################
resource "aws_route53_record" "alb" {
  count   = var.hosted_zone_id != null ? 1 : 0
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.alb.dns_name
    zone_id                = aws_lb.alb.zone_id
    evaluate_target_health = true
  }
}
