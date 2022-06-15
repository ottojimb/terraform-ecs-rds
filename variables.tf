variable "aws_region" {
  default = "us-east-1"
}

variable "project" {
  default = "nauty2"
}

variable "subproject" {
  default = "backend"
}

variable "password_db" {
  default = "password"
}

variable "ecs_acm_arn" {
  default = "ecs_acm_arn"
}

variable "image_port" {
  default = "3000"
}
