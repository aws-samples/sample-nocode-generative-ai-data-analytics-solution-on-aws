# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

locals {
  app_name       = "streamlit-ui"
  container_port = 8501
}

################################################################################
# Streamlit Docker image
################################################################################
module "streamlit_docker_image" {
  source = "../docker_image"

  name               = "code-interpreter-streamlit-ui"
  region             = var.region
  ecr_kms_key_arn    = var.ecs_kms_key_arn
  build_context_path = var.streamlit_src_path
}

################################################################################
# ECS
################################################################################
# Create ECS Cluster
module "ecs_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.2"

  name        = "ecs-sg"
  description = "Security group for ECS with Streamlit UI port open within VPC"
  vpc_id      = var.vpc_id


  ingress_with_cidr_blocks = [
    {
      from_port   = local.container_port
      to_port     = local.container_port
      protocol    = "tcp"
      description = "Streamlit UI"
      cidr_blocks = data.aws_vpc.vpc.cidr_block
    }
  ]

  egress_rules       = ["https-443-tcp"]
  egress_cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_ecs_cluster" "streamlit_ecs_cluster" {
  name = "${local.app_name}-ecs-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "streamlit_ecs_cluster" {
  cluster_name       = aws_ecs_cluster.streamlit_ecs_cluster.name
  capacity_providers = ["FARGATE"]
  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# Create ECS Service
resource "aws_ecs_service" "streamlit_ecs_service" {
  name            = "${local.app_name}-ecs-service"
  cluster         = aws_ecs_cluster.streamlit_ecs_cluster.id
  task_definition = aws_ecs_task_definition.streamlit_ecs_task_definition.arn
  desired_count   = 1 # Number of tasks to run
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.subnet_ids
    security_groups = [module.ecs_sg.security_group_id]
  }

  load_balancer {
    target_group_arn = var.alb_target_group_arn
    container_name   = "${local.app_name}-container"
    container_port   = local.container_port
  }

  tags = {
    Name = "${local.app_name}-ecs-service"
  }
}

# Create CloudWatch Log Group for ECS
resource "aws_cloudwatch_log_group" "streamlit_ecs_service_log_group" {
  name              = "/ecs/${local.app_name}-ecs-log-group"
  retention_in_days = 30
  kms_key_id        = var.ecs_kms_key_arn

  tags = {
    Name = "/ecs/${local.app_name}-ecs-log-group"
  }
}

# Create ECS Task
resource "aws_ecs_task_definition" "streamlit_ecs_task_definition" {
  family                   = "${local.app_name}-ecs-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  task_role_arn            = aws_iam_role.ecs_default_role.arn
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "${local.app_name}-container",
      image     = module.streamlit_docker_image.image_uri
      essential = true,
      environment = [
        {
          name  = "API_BASE_PATH",
          value = var.api_base_path
        }
      ],
      portMappings = [
        {
          containerPort = local.container_port,
          hostPort      = local.container_port,
          protocol      = "tcp"
        }
      ],

      logConfiguration = {
        logDriver = "awslogs",
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.streamlit_ecs_service_log_group.name,
          "awslogs-region"        = var.region,
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }
}


# - Roles -
data "aws_iam_policy_document" "ecs_tasks_trust_relationship" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_default_role" {
  name               = "${local.app_name}-ecs-default-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust_relationship.json
}

resource "aws_iam_role_policy_attachment" "ecs_default_role" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "${local.app_name}-ecs-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust_relationship.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
