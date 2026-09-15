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

