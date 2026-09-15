resource "aws_ecs_cluster" "streamforge" {
  name = "streamforge-dev"

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
  family                   = "streamforge-api-dev"
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

      image = "${aws_ecr_repository.streamforge.repository_url}@sha256:4ff7d32e09de8215c325aa1415ddf0fe6b0f4c65b19a7a62d8c0957f5ba878ab"

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
          value = "us-west-2"
        },
        {
          name  = "SQS_QUEUE_URL"
          value = aws_sqs_queue.processing.id
        },
        {
          name  = "DB_PORT"
          value = "5432"
        },
        {
          name  = "DB_USER"
          value = "postgres"
        },
        {
          name  = "DB_NAME"
          value = "streamforge"
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
          "awslogs-group"         = aws_cloudwatch_log_group.api.name
          "awslogs-region"        = "us-west-2"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "worker" {
  family                   = "streamforge-worker-dev"
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

      image = "${aws_ecr_repository.streamforge.repository_url}@sha256:053d5bef7f711287b29f0c66a50a174c2cbe6de5b66e611c8062a446078abdb7"

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
          value = "us-west-2"
        },
        {
          name  = "SQS_QUEUE_URL"
          value = aws_sqs_queue.processing.id
        },
        {
          name  = "DB_PORT"
          value = "5432"
        },
        {
          name  = "DB_USER"
          value = "postgres"
        },
        {
          name  = "DB_NAME"
          value = "streamforge"
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
          "awslogs-group"         = aws_cloudwatch_log_group.worker.name
          "awslogs-region"        = "us-west-2"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "api" {
  name            = "streamforge-api-dev"
  cluster         = aws_ecs_cluster.streamforge.id
  task_definition = "${aws_ecs_task_definition.api.family}:${aws_ecs_task_definition.api.revision}"

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
    subnets = [
      "subnet-036ac47e687046e4f",
      "subnet-0b56f5f4079edde72",
      "subnet-0752cc2dcb7b3c6db",
      "subnet-0d00f5413bbf44517"
    ]

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
    subnets = [
      "subnet-036ac47e687046e4f",
      "subnet-0b56f5f4079edde72",
      "subnet-0752cc2dcb7b3c6db",
      "subnet-0d00f5413bbf44517"
    ]

    security_groups = [
      aws_security_group.worker.id
    ]

    assign_public_ip = true
  }
}

