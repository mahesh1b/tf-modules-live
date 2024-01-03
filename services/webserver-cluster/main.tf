# terraform {
#   backend "s3" {
#     # Replace this with your bucket name!
#     # bucket = "terraform-up-and-running-state-3180407743"
#     # key    = "modules/services/webserver/terraform.tfstate"
#     bucket = "terraform-up-and-running-state-3180407743"
#     key    = "modules/services/webserver/terraform.tfstate"
#     region = "us-east-1"
#     # Replace this with your DynamoDB table name!
#     dynamodb_table = "terraform-up-and-running-locks"
#     encrypt        = true
#   }
# }

data "terraform_remote_state" "db" {
  backend = "local"
  config = {
    path = "../../../stage/data-stores/mysql/terraform.tfstate"
  }
}


resource "aws_launch_configuration" "example" {
  image_id        = var.ami
  instance_type   = var.instance_type
  security_groups = [aws_security_group.instance.id]

  # Render the User Data script as a template
  user_data = templatefile("${path.module}/init.sh", {
    server_text = var.server_text
    server_port = var.port
    db_address  = data.terraform_remote_state.db.outputs.address
    db_port     = data.terraform_remote_state.db.outputs.port
  })

}


resource "aws_autoscaling_group" "example" {
  # Explicitly depend on the launch configuration's name so eachtime it's
  # replaced, this ASG is also replaced
  name = "${var.cluster_name}-${aws_launch_configuration.example.name}"

  launch_configuration = aws_launch_configuration.example.name
  vpc_zone_identifier  = data.aws_subnets.default.ids
  target_group_arns    = [aws_lb_target_group.asg.arn]
  health_check_type    = "ELB"


  min_size = var.min_size
  max_size = var.max_size

  # considering the ASG deployment complete
  min_elb_capacity = var.min_size
  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-asg"
    propagate_at_launch = true
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb" "example" {
  name               = "${var.cluster_name}-alb"
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default.ids
  security_groups    = [aws_security_group.alb.id]

}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port              = local.http_port
  protocol          = "HTTP"
  # By default, return a simple 404 page
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = 404
    }
  }
}

resource "aws_lb_target_group" "asg" {
  name     = "${var.cluster_name}-lb-target-group"
  port     = var.port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id
  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100
  condition {
    path_pattern {
      values = ["*"]
    }
  }
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}


resource "aws_security_group" "alb" {
  name = "${var.cluster_name}-sg"
  # Allow inbound HTTP requests
  ingress {
    from_port   = local.http_port
    to_port     = local.http_port
    protocol    = local.tcp_protocol
    cidr_blocks = local.all_ips
  }
  # Allow all outbound requests
  egress {
    from_port   = local.any_port
    to_port     = local.any_port
    protocol    = local.any_protocol
    cidr_blocks = local.all_ips
  }
}

resource "aws_security_group" "instance" {
  name = "${var.cluster_name}-sg-for-ec2"
  ingress {
    from_port   = var.port
    to_port     = var.port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}
