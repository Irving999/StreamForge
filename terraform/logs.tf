resource "aws_cloudwatch_log_group" "api" {
  name = "/ecs/streamforge-api-dev"
}

resource "aws_cloudwatch_log_group" "worker" {
  name = "/ecs/streamforge-worker-dev"
}

