resource "aws_ecs_cluster" "streamforge" {
  name = local.base_name

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  configuration {
    execute_command_configuration {
      logging = "DEFAULT"
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "streamforge" {
  cluster_name = aws_ecs_cluster.streamforge.name

  capacity_providers = [
    "FARGATE",
    "FARGATE_SPOT"
  ]
}

resource "aws_ecs_task_definition" "api" {
  family                   = local.api_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  cpu    = "256"
  memory = "512"

  task_role_arn      = aws_iam_role.api_task.arn
  execution_role_arn = aws_iam_role.ecs_execution.arn

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name      = "api"
      essential = true

      image = "${aws_ecr_repository.streamforge.repository_url}@${var.image_digest}"

      environmentFiles = []
      mountPoints      = []
      systemControls   = []
      ulimits          = []
      volumesFrom      = []

      portMappings = [
        {
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
          name          = "api-8000-tcp"
          appProtocol   = "http"
        }
      ]

      environment = [
        {
          name  = "S3_BUCKET"
          value = aws_s3_bucket.media.bucket
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "SQS_QUEUE_URL"
          value = aws_sqs_queue.processing.id
        },
        {
          name  = "DB_PORT"
          value = local.db_port
        },
        {
          name  = "DB_USER"
          value = local.db_user
        },
        {
          name  = "DB_NAME"
          value = local.db_name
        },
        {
          name  = "DB_HOST"
          value = aws_db_instance.postgres.address
        }
      ]

      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = "${data.aws_secretsmanager_secret.rds_credentials.arn}:password::"
        }
      ]

      logConfiguration = {
        logDriver     = "awslogs"
        secretOptions = []

        options = {
          "awslogs-create-group"  = "true"
          "awslogs-group"         = aws_cloudwatch_log_group.api.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "worker" {
  family                   = local.worker_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  cpu    = "1024"
  memory = "2048"

  task_role_arn      = aws_iam_role.worker_task.arn
  execution_role_arn = aws_iam_role.ecs_execution.arn

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name             = "worker"
      essential        = true
      workingDirectory = "/app"

      image = "${aws_ecr_repository.streamforge.repository_url}@${var.image_digest}"

      command = [
        "python",
        "-u",
        "worker.py"
      ]

      portMappings     = []
      environmentFiles = []
      mountPoints      = []
      systemControls   = []
      ulimits          = []
      volumesFrom      = []

      environment = [
        {
          name  = "S3_BUCKET"
          value = aws_s3_bucket.media.bucket
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "SQS_QUEUE_URL"
          value = aws_sqs_queue.processing.id
        },
        {
          name  = "DB_PORT"
          value = local.db_port
        },
        {
          name  = "DB_USER"
          value = local.db_user
        },
        {
          name  = "DB_NAME"
          value = local.db_name
        },
        {
          name  = "DB_HOST"
          value = aws_db_instance.postgres.address
        }
      ]

      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = "${data.aws_secretsmanager_secret.rds_credentials.arn}:password::"
        }
      ]

      logConfiguration = {
        logDriver     = "awslogs"
        secretOptions = []

        options = {
          "awslogs-create-group"  = "true"
          "awslogs-group"         = aws_cloudwatch_log_group.worker.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "api" {
  name            = local.api_name
  cluster         = aws_ecs_cluster.streamforge.id
  task_definition = "${aws_ecs_task_definition.api.family}:${aws_ecs_task_definition.api.revision}"

  wait_for_steady_state = true

  desired_count       = 1
  launch_type         = "FARGATE"
  platform_version    = "LATEST"
  scheduling_strategy = "REPLICA"

  enable_ecs_managed_tags = true
  enable_execute_command  = false

  availability_zone_rebalancing = "ENABLED"

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_controller {
    type = "ECS"
  }

  health_check_grace_period_seconds = 30

  network_configuration {
    subnets = var.alb_subnet_ids

    security_groups = [
      aws_security_group.api.id
    ]

    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = 8000
  }

  depends_on = [
    aws_lb_listener.api_http
  ]
}

resource "aws_ecs_service" "worker" {
  name    = "streamforge-worker-dev-service-6l8fdvnh"
  cluster = aws_ecs_cluster.streamforge.id

  task_definition = "${aws_ecs_task_definition.worker.family}:${aws_ecs_task_definition.worker.revision}"

  wait_for_steady_state = true

  desired_count       = 1
  platform_version    = "LATEST"
  scheduling_strategy = "REPLICA"

  enable_ecs_managed_tags = true
  enable_execute_command  = false

  availability_zone_rebalancing = "ENABLED"

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_controller {
    type = "ECS"
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 0
  }

  network_configuration {
    subnets = var.subnet_ids

    security_groups = [
      aws_security_group.worker.id
    ]

    assign_public_ip = true
  }
}
