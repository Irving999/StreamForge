resource "aws_iam_role" "api_task" {
  name        = "${local.project}-api-task-role"
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
  name = "${local.project}-api-task-rolePolicy"
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
  name = "${local.project}/${local.environment}/rds-credentials"
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
