resource "aws_db_instance" "postgres" {
  identifier = local.base_name

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
    Environment = local.environment
    Project     = local.project
  }

  vpc_security_group_ids = [aws_security_group.rds.id]
}
