terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

resource "aws_sqs_queue" "processing" {
  name                       = "streamforge-processing-dev"
  visibility_timeout_seconds = 600
  max_message_size           = 1048576
}

resource "aws_sqs_queue" "processing_dlq" {
  name                      = "streamforge-processing-dlq-dev"
  message_retention_seconds = 1209600
  max_message_size          = 1048576
}

resource "aws_sqs_queue_redrive_policy" "processing" {
  queue_url = aws_sqs_queue.processing.id

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.processing_dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "processing_dlq" {
  queue_url = aws_sqs_queue.processing_dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.processing.arn]
  })
}

resource "aws_s3_bucket" "media" {
  bucket = "streamforge-879807128870-us-west-2-an"
}

resource "aws_s3_bucket_public_access_block" "media" {
  bucket = aws_s3_bucket.media.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_db_instance" "postgres" {
  identifier = "streamforge-dev"

  engine         = "postgres"
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  storage_type      = "gp2"
  storage_encrypted = true

  db_name  = "streamforge"
  username = "postgres"
  port     = 5432

  publicly_accessible     = true
  backup_retention_period = 1
  deletion_protection     = false

  apply_immediately            = false
  copy_tags_to_snapshot        = true
  max_allocated_storage        = 1000
  performance_insights_enabled = true
  skip_final_snapshot          = true

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Environment = "dev"
    Project     = "streamforge"
  }

  vpc_security_group_ids = [aws_security_group.rds.id]
}

resource "aws_ecr_repository" "streamforge" {
  name = "streamforge"
}

resource "aws_iam_role" "api_task" {
  name        = "streamforge-api-task-role"
  description = "Allows ECS tasks to call AWS services on your behalf."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "api_task_access" {
  name = "streamforge-api-task-rolePolicy"
  role = aws_iam_role.api_task.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "UploadVideos"
        Effect = "Allow"

        Action = [
          "s3:PutObject",
          "s3:DeleteObject"
        ]

        Resource = "${aws_s3_bucket.media.arn}/uploads/*"
      },
      {
        Sid    = "SendJobs"
        Effect = "Allow"

        Action = [
          "sqs:SendMessage"
        ]

        Resource = aws_sqs_queue.processing.arn
      }
    ]
  })
}

resource "aws_iam_role" "worker_task" {
  name = "ecs-tasks.amazonaws.com"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }

        Action = "sts:AssumeRole"

        Condition = {
          ArnLike = {
            "aws:SourceArn" = "arn:aws:ecs:us-west-2:879807128870:*"
          }

          StringEquals = {
            "aws:SourceAccount" = "879807128870"
          }
        }
      }
    ]
  })
}

resource "aws_iam_policy" "worker_task" {
  name = "ecs-tasks.amazonaws.comPolicy"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]

        Resource = [
          "${aws_s3_bucket.media.arn}/uploads/*",
          "${aws_s3_bucket.media.arn}/outputs/*"
        ]
      },
      {
        Effect = "Allow"

        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:ChangeMessageVisibility",
          "sqs:GetQueueAttributes"
        ]

        Resource = aws_sqs_queue.processing.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "worker_task" {
  role       = aws_iam_role.worker_task.name
  policy_arn = aws_iam_policy.worker_task.arn
}

resource "aws_iam_role" "ecs_execution" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2008-10-17"

    Statement = [
      {
        Sid    = ""
        Effect = "Allow"

        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_secretsmanager_secret" "rds_credentials" {
  name = "streamforge/dev/rds-credentials"
}

resource "aws_iam_role_policy" "ecs_execution_secret" {
  name = "StreamForgeReadRDSSecret"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "secretsmanager:GetSecretValue"
        ]

        Resource = data.aws_secretsmanager_secret.rds_credentials.arn
      }
    ]
  })
}

resource "aws_security_group" "alb" {
  name        = "streamforge-alb-dev"
  description = "Allows HTTP access to StreamForge ALB"
  vpc_id      = "vpc-071a5d81d3bb8828e"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http_from_home" {
  security_group_id = aws_security_group.alb.id

  cidr_ipv4   = "73.162.217.228/32"
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_all_outbound" {
  security_group_id = aws_security_group.alb.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_security_group" "api" {
  name        = "streamforge-api-dev"
  description = "Allows temporary API access on port 8000 from my IP"
  vpc_id      = "vpc-071a5d81d3bb8828e"
}

resource "aws_vpc_security_group_ingress_rule" "api_from_alb" {
  security_group_id = aws_security_group.api.id

  referenced_security_group_id = aws_security_group.alb.id

  from_port   = 8000
  to_port     = 8000
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "api_all_outbound" {
  security_group_id = aws_security_group.api.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_security_group" "worker" {
  name        = "streamforge-worker-dev"
  description = "Security group for StreamForge Fargate worker"
  vpc_id      = "vpc-071a5d81d3bb8828e"
}

resource "aws_vpc_security_group_egress_rule" "worker_all_outbound" {
  security_group_id = aws_security_group.worker.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_security_group" "rds" {
  name        = "streamforge-rds-dev"
  description = "Created by RDS management console"
  vpc_id      = "vpc-071a5d81d3bb8828e"
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_api" {
  security_group_id = aws_security_group.rds.id

  referenced_security_group_id = aws_security_group.api.id

  from_port   = 5432
  to_port     = 5432
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_worker" {
  security_group_id = aws_security_group.rds.id

  referenced_security_group_id = aws_security_group.worker.id

  from_port   = 5432
  to_port     = 5432
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_home" {
  security_group_id = aws_security_group.rds.id

  cidr_ipv4   = "73.162.217.228/32"
  from_port   = 5432
  to_port     = 5432
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "rds_all_outbound" {
  security_group_id = aws_security_group.rds.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_lb" "api" {
  name               = "streamforge-api-dev"
  internal           = false
  load_balancer_type = "application"
  ip_address_type    = "ipv4"

  security_groups = [
    aws_security_group.alb.id
  ]

  subnets = [
    "subnet-0b56f5f4079edde72",
    "subnet-0d00f5413bbf44517"
  ]

  enable_deletion_protection = false
  idle_timeout               = 60
}

resource "aws_lb_target_group" "api" {
  name             = "streamforge-api-dev"
  port             = 8000
  protocol         = "HTTP"
  protocol_version = "HTTP1"
  target_type      = "ip"
  vpc_id           = "vpc-071a5d81d3bb8828e"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    port                = "traffic-port"
    path                = "/docs"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "api_http" {
  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn

    forward {
      target_group {
        arn    = aws_lb_target_group.api.arn
        weight = 1
      }

      stickiness {
        enabled  = false
        duration = 3600
      }
    }
  }
}

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

resource "aws_cloudwatch_log_group" "api" {
  name = "/ecs/streamforge-api-dev"
}

resource "aws_cloudwatch_log_group" "worker" {
  name = "/ecs/streamforge-worker-dev"
}