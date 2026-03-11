terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ─── VPC ────────────────────────────────────────────────────────────────────
resource "aws_vpc" "k8s" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${var.cluster_name}-vpc" }
}

resource "aws_internet_gateway" "k8s" {
  vpc_id = aws_vpc.k8s.id
  tags   = { Name = "${var.cluster_name}-igw" }
}

resource "aws_subnet" "k8s_public" {
  vpc_id                  = aws_vpc.k8s.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = { Name = "${var.cluster_name}-public-subnet" }
}

resource "aws_route_table" "k8s" {
  vpc_id = aws_vpc.k8s.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.k8s.id
  }
  tags = { Name = "${var.cluster_name}-rt" }
}

resource "aws_route_table_association" "k8s" {
  subnet_id      = aws_subnet.k8s_public.id
  route_table_id = aws_route_table.k8s.id
}

# ─── SECURITY GROUPS ────────────────────────────────────────────────────────
resource "aws_security_group" "k8s_master" {
  name        = "${var.cluster_name}-master-sg"
  description = "Security group for Kubernetes master node"
  vpc_id      = aws_vpc.k8s.id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }
  # Kubernetes API Server
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # etcd
  ingress {
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    self        = true
    cidr_blocks = ["10.0.0.0/16"]
  }
  # Kubelet API, Scheduler, Controller Manager
  ingress {
    from_port   = 10250
    to_port     = 10259
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  # Flannel VXLAN (CNI)
  ingress {
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.cluster_name}-master-sg" }
}

resource "aws_security_group" "k8s_worker" {
  name        = "${var.cluster_name}-worker-sg"
  description = "Security group for Kubernetes worker node"
  vpc_id      = aws_vpc.k8s.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }
  # Kubelet API
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  # NodePort range
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Flannel VXLAN (CNI)
  ingress {
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.cluster_name}-worker-sg" }
}

# ─── KEY PAIR ───────────────────────────────────────────────────────────────
resource "aws_key_pair" "k8s" {
  key_name   = "${var.cluster_name}-key"
  public_key = file(var.public_key_path)
}

# ─── DATA: Amazon Linux 2023 AMI ────────────────────────────────────────────
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-6.1-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ─── MASTER NODE ────────────────────────────────────────────────────────────
resource "aws_instance" "master" {
  ami = var.ami_id
  instance_type          = var.master_instance_type
  subnet_id              = aws_subnet.k8s_public.id
  key_name               = aws_key_pair.k8s.key_name
  vpc_security_group_ids = [aws_security_group.k8s_master.id]

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/scripts/master.sh", {
    cluster_name    = var.cluster_name
    pod_network_cidr = var.pod_network_cidr
    k8s_version     = var.k8s_version
  })

  tags = {
    Name = "${var.cluster_name}-master"
    Role = "master"
  }
}

# ─── WORKER NODE ────────────────────────────────────────────────────────────
resource "aws_instance" "worker" {
  ami = var.ami_id
  instance_type          = var.worker_instance_type
  subnet_id              = aws_subnet.k8s_public.id
  key_name               = aws_key_pair.k8s.key_name
  vpc_security_group_ids = [aws_security_group.k8s_worker.id]

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/scripts/worker.sh", {
    k8s_version = var.k8s_version
  })

  tags = {
    Name = "${var.cluster_name}-worker"
    Role = "worker"
  }

  depends_on = [aws_instance.master]
}
