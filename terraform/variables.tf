variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "vpc_id" {
  type    = string
  default = "vpc-071a5d81d3bb8828e"
}

variable "subnet_ids" {
  type = list(string)

  default = [
    "subnet-036ac47e687046e4f",
    "subnet-0b56f5f4079edde72",
    "subnet-0752cc2dcb7b3c6db",
    "subnet-0d00f5413bbf44517"
  ]
}

variable "home_cidr" {
  type    = string
  default = "73.162.217.228/32"
}

variable "alb_subnet_ids" {
  type = list(string)

  default = [
    "subnet-0b56f5f4079edde72",
    "subnet-0d00f5413bbf44517"
  ]
}