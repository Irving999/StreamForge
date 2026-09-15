locals {
  project     = "streamforge"
  environment = "dev"

  base_name                 = "${local.project}-${local.environment}"
  api_name                  = "${local.project}-api-${local.environment}"
  worker_name               = "${local.project}-worker-${local.environment}"
  alb_name                  = "${local.project}-alb-${local.environment}"
  rds_name                  = "${local.project}-rds-${local.environment}"
  processing_queue_name     = "${local.project}-processing-${local.environment}"
  processing_dlq_queue_name = "${local.project}-processing-dlq-${local.environment}"

  db_name = "streamforge"
  db_user = "postgres"
  db_port = "5432"
}
