resource "aws_cloudwatch_log_group" "api" {
  name = "/ecs/${local.api_name}"
}

resource "aws_cloudwatch_log_group" "worker" {
  name = "/ecs/${local.worker_name}"
}
