# VPC
resource "aws_vpc" "main" {
  cidr_block = "10.10.0.0/16"
  tags = { Name = "My-Vpc" }
}


# Public Subnets
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.10.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
  tags                    = { Name = "Public-Subnet-1" }
}

resource "aws_subnet" "public1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.10.2.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1b"
  tags                    = { Name = "Public-Subnet-2" }
}

# Private Subnets
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.10.3.0/24"
  availability_zone = "us-east-1a"
  tags              = { Name = "Private-Subnet-1" }
}

resource "aws_subnet" "private1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.10.4.0/24"
  availability_zone = "us-east-1b"
  tags              = { Name = "Private-Subnet-2" }
}


# Security Groups
resource "aws_security_group" "public_sg_vpc" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "Public-SG" }
}

resource "aws_security_group" "private_sg_vpc" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "Private-SG" }
}


# InterNet-Gateway
resource "aws_internet_gateway" "my-IGW" {
    vpc_id    = aws_vpc.main.id
    tags      = {Name    = "My-IGW"}
  
}


# Route-Table
resource "aws_route_table" "public" {
  vpc_id      = aws_vpc.main.id
  tags        = {Name = "MRT"}
}

# Edit-Routes
resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"  # Default route for internet traffic
  gateway_id             = aws_internet_gateway.my-IGW.id
}

# Subnet-Association Public-Subnet-01 with Public Route Table
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
# Associate Public-Subnet-02 with Public Route Table
resource "aws_route_table_association" "public_assoc_2" {
  subnet_id      = aws_subnet.public1.id
  route_table_id = aws_route_table.public.id
}


# Allocate an Elastic IP for the NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"
  tags = {
    Name = "NAT-EIP"
  }
}


# Create the NAT Gateway in the Public Subnet
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "NAT-Gateway"
  }

  depends_on = [aws_internet_gateway.my-IGW]
}


# Private Route Table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "CRT"
  }
}

# Edit-Routes
resource "aws_route" "private_nat_route" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"  # Default route for internet traffic
  nat_gateway_id         = aws_nat_gateway.nat_gw.id
}

# Subnet-Association First Private Subnet
resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}
# Subnet-Association Second Private Subnet
resource "aws_route_table_association" "private_assoc2" {
  subnet_id      = aws_subnet.private1.id
  route_table_id = aws_route_table.private.id
}




##########    EC2  #############################


# Variables

variable "sg_ports" {
  type        = list(number)
  description = "List of ingress ports"
  default     = [80, 22]
}



# AMI
data "aws_ami" "amazon_linux" {
  most_recent = true

  filter {
    name   = "name"
    values = ["al2023-ami-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  owners = ["amazon"]
}

# Key Pair
resource "aws_key_pair" "deployer" {
  key_name   = "mykey-new"
  public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHytR9/71L3jn/5Qj9QW6ue2nShgSu3kLUYOVzAJLuZ8 Sanket@LAPTOP-QUR2N0FG"
}

# Security Group for Public Instances
resource "aws_security_group" "public_sg" {
  name        = "Public-EC2-SG"
  vpc_id      = aws_vpc.main.id
  description = "Allow public traffic"

  dynamic "ingress" {
    for_each = var.sg_ports
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security Group for Private Instances
resource "aws_security_group" "private_sg" {
  name        = "Private-EC2-SG"
  vpc_id      = aws_vpc.main.id
  description = "Private instance access within VPC"

  dynamic "ingress" {
    for_each = var.sg_ports
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = [var.vpc_cidr]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# User Data Script (Install Apache and MariaDB)
locals {
  user_data = <<-EOT
    #!/bin/bash
    yum update -y
    yum install -y httpd php php-mysqlnd mariadb-server
    systemctl start httpd
    systemctl enable httpd
    systemctl start mariadb
    systemctl enable mariadb
  EOT
}

# Public EC2 Instance 1
resource "aws_instance" "public_instance_1" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.public_sg.id]
  associate_public_ip_address = true
  user_data              = local.user_data

  tags = {
    Name = "Public-Instance-1"
  }
}

# Public EC2 Instance 2
resource "aws_instance" "public_instance_2" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public1.id
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.public_sg.id]
  associate_public_ip_address = true
  user_data              = local.user_data

  tags = {
    Name = "Public-Instance-2"
  }
}

# Private EC2 Instance 1
resource "aws_instance" "private_instance_1" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.private_sg.id]
  user_data              = local.user_data

  tags = {
    Name = "Private-Instance-1"
  }
}

# Private EC2 Instance 2
resource "aws_instance" "private_instance_2" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private1.id
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.private_sg.id]
  user_data              = local.user_data

  tags = {
    Name = "Private-Instance-2"
  }
}





# Create an AMI from Public EC2-1
resource "aws_ami_from_instance" "public_instance_1_ami" {
  name               = "public-instance-1-ami"
  source_instance_id = aws_instance.public_instance_1.id
}



# Launch Template using the created AMI
resource "aws_launch_template" "public_instance_template" {
  name_prefix            = "public-instance-"
  image_id               = aws_ami_from_instance.public_instance_1_ami.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.public_sg.id]
  user_data              = base64encode(local.user_data)

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "Public-Instance-Template"
    }
  }
}


# Target Group for Public EC2 Instances
resource "aws_lb_target_group" "public_ec2_target_group" {
  name     = "public-ec2-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  target_type = "instance"
}

# Attach Public EC2 Instances to Target Group
resource "aws_lb_target_group_attachment" "public_instance_1_attachment" {
  target_group_arn = aws_lb_target_group.public_ec2_target_group.arn
  target_id        = aws_instance.public_instance_1.id
  port            = 80
}

resource "aws_lb_target_group_attachment" "public_instance_2_attachment" {
  target_group_arn = aws_lb_target_group.public_ec2_target_group.arn
  target_id        = aws_instance.public_instance_2.id
  port            = 80
}


# Application Load Balancer
resource "aws_lb" "public_alb" {
  name               = "public-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.public_sg.id]
  subnets            = [aws_subnet.public.id, aws_subnet.public1.id]
}

resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.public_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.public_ec2_target_group.arn
  }
}





# Combined Auto Scaling Group for Public EC2 Instances
resource "aws_launch_template" "public_ec2_template" {
  name_prefix   = "public-ec2-template"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.deployer.key_name

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.public_sg.id]
  }
}

resource "aws_autoscaling_group" "public_ec2_asg" {
  desired_capacity     = 2
  max_size            = 4
  min_size            = 2
  vpc_zone_identifier = [aws_subnet.public.id, aws_subnet.public1.id]

  launch_template {
    id      = aws_launch_template.public_ec2_template.id
    version = "$Latest"
  }
}





# Target Group for Private EC2 Instances
resource "aws_lb_target_group" "private_ec2_target_group" {
  name        = "private-ec2-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"
}

# Attach Private EC2 Instances to Target Group
resource "aws_lb_target_group_attachment" "private_instance_1_attachment" {
  target_group_arn = aws_lb_target_group.private_ec2_target_group.arn
  target_id        = aws_instance.private_instance_1.id
  port            = 80
}

resource "aws_lb_target_group_attachment" "private_instance_2_attachment" {
  target_group_arn = aws_lb_target_group.private_ec2_target_group.arn
  target_id        = aws_instance.private_instance_2.id
  port            = 80
}


# Application Load Balancer for Private Instances
resource "aws_lb" "private_alb" {
  name               = "private-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.private_sg.id]
  subnets            = [aws_subnet.private.id, aws_subnet.private1.id]

  enable_deletion_protection = false
}

# Listener for Private ALB
resource "aws_lb_listener" "private_alb_listener" {
  load_balancer_arn = aws_lb.private_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.private_ec2_target_group.arn
  }
}



# Combined Auto Scaling Group for Private EC2 Instances
resource "aws_launch_template" "private_ec2_template" {
  name_prefix   = "private-ec2-template"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.deployer.key_name

  network_interfaces {
    security_groups = [aws_security_group.private_sg.id]
  }
}

resource "aws_autoscaling_group" "private_ec2_asg" {
  desired_capacity     = 2
  max_size            = 4
  min_size            = 2
  vpc_zone_identifier = [aws_subnet.private.id, aws_subnet.private1.id]

  launch_template {
    id      = aws_launch_template.private_ec2_template.id
    version = "$Latest"
  }
}
