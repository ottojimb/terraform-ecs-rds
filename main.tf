resource "aws_s3_bucket" "tfbucket" {
  bucket = "${var.project}-${var.subproject}-tfstate"

  lifecycle {
    # prevent_destroy = true
  }

  tags = {
    "project"   = "${var.project}"
    "subproject"   = "${var.subproject}"
    "workspace" = "${terraform.workspace}"
  }
}

resource "aws_s3_bucket_versioning" "tfbucket" {
  bucket = aws_s3_bucket.tfbucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket" "env_vars" {
  bucket = "${var.project}-${var.subproject}-env"

  lifecycle {
    # prevent_destroy = true
  }

  tags = {
    "project"   = "${var.project}"
    "subproject"   = "${var.subproject}"
    "workspace" = "${terraform.workspace}"
  }
}

terraform {
  # backend "s3" {
  #   bucket = "${var.project}-tfstate"
  #   key    = "terraform/${terraform.workspace}_key"
  #   region = var.aws_region
  #   encrypt = true
  # }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "aws_ecr_repository" "custom_ecr_repository" {
  name                 = "${var.project}-${var.subproject}-${terraform.workspace}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = {
    "project"   = "${var.project}"
    "subproject"   = "${var.subproject}"
    "workspace" = "${terraform.workspace}"
  }
}

resource "aws_ecs_cluster" "custom_cluster" {
  name = "${terraform.workspace}-v1"

  tags = {
    "project"   = "${var.project}"
    "workspace" = "${terraform.workspace}"
  }
}

resource "aws_cloudwatch_log_group" "log" {
  name = "awslogs-${var.project}-${var.subproject}-${terraform.workspace}"

  tags = {
    "project"   = "${var.project}"
    "subproject"   = "${var.subproject}"
    "workspace" = "${terraform.workspace}"
  }
}

resource "aws_ecs_task_definition" "custom_ecs_task" {
  family                   = "${var.project}-${var.subproject}-${terraform.workspace}"
  container_definitions    = <<DEFINITION
  [
    {
      "name": "${var.project}-${var.subproject}-${terraform.workspace}",
      "image": "${aws_ecr_repository.custom_ecr_repository.repository_url}",
      "essential": true,
      "portMappings": [
        {
          "containerPort": ${var.image_port},
          "hostPort": ${var.image_port}
        }
      ],
      "environmentFiles": [
        {
          "value":  "arn:aws:s3:::${var.project}-${var.subproject}-env/${terraform.workspace}.env",
          "type": "s3"
        }
      ],
      "memory": 512,
      "cpu": 256,
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "${aws_cloudwatch_log_group.log.name}",
          "awslogs-region": "${var.aws_region}",
          "awslogs-stream-prefix": "awslogs-${var.project}-${var.subproject}-${terraform.workspace}"
        }
      }
    }
  ]
  DEFINITION
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  memory                   = 512
  cpu                      = 256
  execution_role_arn       = aws_iam_role.ecsTaskExecutionRole.arn

  tags = {
    "project"   = "${var.project}"
    "subproject"   = "${var.subproject}"
    "workspace" = "${terraform.workspace}"
  }
}

resource "aws_iam_role" "ecsTaskExecutionRole" {
  name               = "ecsTaskExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json

  tags = {
    "project"   = "${var.project}"
    "workspace" = "${terraform.workspace}"
  }
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "s3_env_vars" {
  name        = "custom-policy"
  description = "A custom policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject"
      ],
      "Resource": [
        "arn:aws:s3:::${var.project}-${var.subproject}-env/${terraform.workspace}.env"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::${var.project}-${var.subproject}-env"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_policy" {
  role       = aws_iam_role.ecsTaskExecutionRole.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "s3_env_vars_policy" {
  role       = aws_iam_role.ecsTaskExecutionRole.name
  policy_arn = aws_iam_policy.s3_env_vars.arn
}

resource "aws_ecs_service" "backend_service" {
  name            = "${var.project}-${var.subproject}-${terraform.workspace}"
  cluster         = aws_ecs_cluster.custom_cluster.id
  task_definition = aws_ecs_task_definition.custom_ecs_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  load_balancer {
    target_group_arn = aws_lb_target_group.target_group.arn
    container_name   = aws_ecs_task_definition.custom_ecs_task.family
    container_port   = var.image_port
  }

  network_configuration {
    subnets          = module.vpc.private_subnets
    assign_public_ip = false
    security_groups  = ["${aws_security_group.service_security_group.id}", "${aws_security_group.load_balancer_security_group.id}"] # Setting the security group
  }

  tags = {
    "project"   = "${var.project}"
    "subproject"   = "${var.subproject}"
    "workspace" = "${terraform.workspace}"
  }
}

resource "aws_alb" "application_load_balancer" {
  name               = "${var.project}-${var.subproject}-${terraform.workspace}"
  load_balancer_type = "application"
  subnets            = module.vpc.public_subnets
  security_groups    = ["${aws_security_group.load_balancer_security_group.id}"]

  tags = {
    "project"   = "${var.project}"
    "subproject"   = "${var.subproject}"
    "workspace" = "${terraform.workspace}"
  }
}

# Creating a security group for the load balancer:
resource "aws_security_group" "load_balancer_security_group" {
  vpc_id = module.vpc.vpc_id
  ingress {
    from_port   = 80 # Allowing traffic in from port 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic in from all sources
  }

  ingress {
    from_port   = 443 # Allowing traffic in from port 80
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic in from all sources
  }

  egress {
    from_port   = 0             # Allowing any incoming port
    to_port     = 0             # Allowing any outgoing port
    protocol    = "-1"          # Allowing any outgoing protocol 
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic out to all IP addresses
  }

  tags = {
    "project"   = "${var.project}"
    "subproject"   = "${var.subproject}"
    "workspace" = "${terraform.workspace}"
  }
}

resource "aws_lb_target_group" "target_group" {
  name        = "${var.project}-${var.subproject}-${terraform.workspace}"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = module.vpc.vpc_id
  health_check {
    matcher  = "200,301,302"
    path     = "/"
    interval = "300"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    "project"   = "${var.project}"
    "subproject"   = "${var.subproject}"
    "workspace" = "${terraform.workspace}"
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_alb.application_load_balancer.arn
  port              = "443"
  protocol          = "HTTPS"

  ssl_policy      = "ELBSecurityPolicy-2016-08"
  certificate_arn = var.ecs_acm_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn
  }

  tags = {
    "project"   = "${var.project}"
    "subproject"   = "${var.subproject}"
    "workspace" = "${terraform.workspace}"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_alb.application_load_balancer.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type = "redirect"

    redirect {
      port        = 443
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = {
    "project"   = "${var.project}"
    "subproject"   = "${var.subproject}"
    "workspace" = "${terraform.workspace}"
  }
}

resource "aws_security_group" "service_security_group" {
  vpc_id = module.vpc.vpc_id # Referencing the default VPC

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    # Only allowing traffic in from the load balancer security group
    security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
  }

  egress {
    from_port   = 0             # Allowing any incoming port
    to_port     = 0             # Allowing any outgoing port
    protocol    = "-1"          # Allowing any outgoing protocol 
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic out to all IP addresses
  }

  tags = {
    "project"   = "${var.project}"
    "subproject"   = "${var.subproject}"
    "workspace" = "${terraform.workspace}"
  }
}
