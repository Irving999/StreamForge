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

