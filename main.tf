provider "aws" {
  region = "ap-south-1"
}

# 1. VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# 2. Subnets
resource "aws_subnet" "subnet_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-south-1a"
}

resource "aws_subnet" "subnet_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-south-1b"
}

# 3. Internet Gateway (optional if public instances)
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

# 4. Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}

# 5. Security Groups

## ALB Security Group
resource "aws_security_group" "alb_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
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

## EC2 Security Group
resource "aws_security_group" "ec2_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

## EFS Security Group
resource "aws_security_group" "efs_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 6. Load Balancers

resource "aws_lb" "alb" {
  name               = "app-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]
}

resource "aws_lb" "nlb" {
  name               = "network-load-balancer"
  internal           = false
  load_balancer_type = "network"
  subnets            = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]
}

# 7. EC2 Instances
resource "aws_instance" "ec2_instances" {
  count = 6

  ami           = "ami-002f6e91abff6eb96"  # Replace with latest
  instance_type = "t2.micro"
  subnet_id     = count.index < 3 ? aws_subnet.subnet_1.id : aws_subnet.subnet_2.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  tags = {
    Name = "EC2-${count.index + 1}"
  }
}

# 8. EFS + Mount Targets
resource "aws_efs_file_system" "efs" {
  creation_token = "efs-shared-storage"
}

resource "aws_efs_mount_target" "efs_mounts" {
  count          = 2
  file_system_id = aws_efs_file_system.efs.id
  subnet_id      = count.index == 0 ? aws_subnet.subnet_1.id : aws_subnet.subnet_2.id
  security_groups = [aws_security_group.efs_sg.id]
}
