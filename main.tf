provider "aws" {
  region = "ap-south-1"  # Choose your region
}

# VPC
resource "aws_vpc" "medusa_vpc" {
  cidr_block = "10.0.0.0/16"
}

# Subnets
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.medusa_vpc.id
  cidr_block        = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone = "ap-south-1b"
}

# Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.medusa_vpc.id
}

# Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.medusa_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "public_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# ECS Cluster
resource "aws_ecs_cluster" "medusa_cluster" {
  name = "medusa-cluster"
}

# ECR Repository
resource "aws_ecr_repository" "medusa_ecr" {
  name = "medusa-repo"
}

# ECS Task Definition
resource "aws_ecs_task_definition" "medusa_task" {
  family                   = "medusa-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = <<DEFINITION
[
  {
    "name": "medusa",
    "image": "${aws_ecr_repository.medusa_ecr.repository_url}:latest",
    "essential": true,
    "portMappings": [
      {
        "containerPort": 9000,
        "hostPort": 9000
      }
    ]
  }
]
DEFINITION
}

# ECS Service
resource "aws_ecs_service" "medusa_service" {
  name            = "medusa-service"
  cluster         = aws_ecs_cluster.medusa_cluster.id
  task_definition = aws_ecs_task_definition.medusa_task.arn
  desired_count   = 1

  network_configuration {
    subnets          = [aws_subnet.public_subnet.id]
    security_groups  = [aws_security_group.medusa_sg.id]
    assign_public_ip = true
  }

#load_balancer {
 #target_group_arn = aws_lb_target_group.medusa_tg.arn
    #container_name   = "medusa"
    #container_port   = 9000
 # }

  launch_type = "FARGATE"
}

# Security Group
resource "aws_security_group" "medusa_sg" {
  vpc_id = aws_vpc.medusa_vpc.id

  ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Load Balancer
#resource "aws_lb" "medusa_lb" {
 # name               = "medusa-lb"
  #internal           = false
 # load_balancer_type = "application"
  #security_groups    = [aws_security_group.medusa_sg.id]
  #subnets            = [aws_subnet.public_subnet.id]
#}

#resource "aws_lb_target_group" "medusa_tg" {
 # name     = "medusa-tg"
 # port     = 9000
 # protocol = "HTTP"
 # vpc_id   = aws_vpc.medusa_vpc.id

 # health_check {
  #  path = "/"
  #}
#}

#resource "aws_lb_listener" "medusa_listener" {
 # load_balancer_arn = aws_lb.medusa_lb.arn
 # port              = "80"
  #protocol          = "HTTP"

 # default_action {
  #  type             = "forward"
   # target_group_arn = aws_lb_target_group.medusa_tg.arn
 # }
#}

# IAM Role for ECS Tasks
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  ]
}
