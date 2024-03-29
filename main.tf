terraform {
    required_version = ">= 1.1.9"
    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = ">= 4.10.0"
        }
    }

    backend "s3" {}
}

data "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
}

resource "aws_ecs_task_definition" "base" {
  family                   = var.task_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = "${data.aws_iam_role.ecs_task_execution_role.arn}"

    container_definitions = jsonencode([
        {
            name      = var.container_name
            image     = local.image
            cpu       = var.container_cpu
            essential = true
            portMappings = [
                {
                containerPort = var.container_port
                protocol      = "tcp"
                hostPort      = var.container_port
                }
            ]
        }
    ])

  runtime_platform {
    operating_system_family = var.task_os_family
    cpu_architecture        = var.task_cpu_architecture
  }

  tags = merge (
      local.tags,
      var.task_tags
  )
}


resource "aws_lb_target_group" "tg-app" {
  name        = var.tg_name
  target_type = "ip"
  vpc_id      = var.aws_vpc_id
  port        = var.tg_port
  protocol    = "HTTP"
  health_check {
    path                = var.tg_health_check_path
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 60
    interval            = 300
    matcher             = "200,301,302"
  }

  tags = merge (
      local.tags,
      var.tg_tags
  )
}

resource "aws_lb_listener_rule" "lr-rule" {
  listener_arn = var.listener_arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg-app.arn
  }

  condition {
    path_pattern {
      values = [var.listener_context_path]
    }
  }
}

resource "aws_ecs_service" "service" {
  name            = var.service_name
  cluster         = var.cluser_name
  task_definition = aws_ecs_task_definition.base.arn
  desired_count   = var.service_desired_count

   load_balancer {
    target_group_arn = aws_lb_target_group.tg-app.arn
    container_name   = var.container_name
    container_port   = var.container_port
  }
  
  # Optional: Allow external changes without Terraform plan difference(for example ASG)
  lifecycle {
    ignore_changes = [desired_count]
  }

  launch_type = "FARGATE"

 network_configuration {
    subnets = var.service_subnets
    security_groups = var.service_sg_ids
    assign_public_ip = true
  }

}