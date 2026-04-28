###############################################################################
# n8n Workspace Corporativo - main.tf
# - VPC + subnet pública
# - EC2 con n8n + Postgres + Caddy (Docker Compose)
# - Postgres en contenedor local (no RDS) con bind configurable
# - Route53 para el dominio
# - Schedules de start/stop con EventBridge
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project     = var.stack_name
      Environment = var.environment_name
      ManagedBy   = "terraform"
    }
  }
}

# ============================================
# Locals
# ============================================
locals {
  name_prefix = var.stack_name
  fqdn        = "${var.subdomain}.${var.root_domain}"
  tags = {
    Project     = var.stack_name
    Environment = var.environment_name
    ManagedBy   = "terraform"
  }
}

# ============================================
# Data sources
# ============================================
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_partition" "current" {}

data "aws_ami" "al2023" {
  owners      = ["amazon"]
  most_recent = true

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_route53_zone" "main" {
  name         = var.root_domain
  private_zone = false
}

# ============================================
# VPC y networking
# ============================================
resource "aws_vpc" "n8n" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-vpc" })
}

resource "aws_internet_gateway" "n8n" {
  vpc_id = aws_vpc.n8n.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-igw" })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.n8n.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-public-subnet" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.n8n.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.n8n.id
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-public-rt" })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ============================================
# Security Group de la EC2
# ============================================
resource "aws_security_group" "n8n" {
  name        = "${local.name_prefix}-public-access"
  description = "Allow HTTP, HTTPS, SSH (optional Postgres) from internet"
  vpc_id      = aws_vpc.n8n.id

  ingress {
    description = "HTTP (Caddy to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH access (can be used for Postgres tunnel)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
  }

  # Solo si postgres_bind = "0.0.0.0" Y hay CIDRs configurados
  dynamic "ingress" {
    for_each = var.postgres_bind == "0.0.0.0" && length(var.postgres_allowed_cidrs) > 0 ? [1] : []
    content {
      description = "Postgres remote access"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = var.postgres_allowed_cidrs
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-sg" })
}

# ============================================
# IAM role para SSM (acceso sin SSH también)
# ============================================
resource "aws_iam_role" "n8n" {
  name_prefix = "${local.name_prefix}-ec2-ssm-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(local.tags, { Name = "${local.name_prefix}-ssm-role" })
}

resource "aws_iam_role_policy_attachment" "n8n_ssm" {
  role       = aws_iam_role.n8n.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "n8n" {
  name_prefix = "${local.name_prefix}-ec2-profile-"
  role        = aws_iam_role.n8n.name
  tags        = merge(local.tags, { Name = "${local.name_prefix}-instance-profile" })
}

# ============================================
# Encryption key auto-generada para n8n
# ============================================
resource "random_password" "encryption_key" {
  length  = 32
  special = false
}

# ============================================
# SSH Key Pair (auto-generada)
# ============================================
resource "tls_private_key" "n8n" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "n8n" {
  key_name   = "${local.name_prefix}-key"
  public_key = tls_private_key.n8n.public_key_openssh

  tags = merge(local.tags, { Name = "${local.name_prefix}-key" })
}

resource "local_file" "private_key" {
  content         = tls_private_key.n8n.private_key_pem
  filename        = "${path.module}/${local.name_prefix}-key.pem"
  file_permission = "0400"
}

# ============================================
# EC2 instance
# ============================================
resource "aws_instance" "n8n" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.n8n.key_name
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.n8n.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.n8n.name

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  ebs_block_device {
    device_name           = "/dev/sdf"
    volume_size           = var.data_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = false
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2
    http_put_response_hop_limit = 1
  }

  user_data = templatefile("${path.module}/scripts/user-data.sh.tftpl", {
    fqdn               = local.fqdn
    timezone           = var.default_timezone
    data_device        = "/dev/xvdf"
    compose_version    = var.docker_compose_version
    letsencrypt_email  = var.letsencrypt_email
    n8n_encryption_key = random_password.encryption_key.result

    # Postgres (contenedor local)
    postgres_password = var.postgres_password
    postgres_bind     = var.postgres_bind

    # SMTP
    smtp_host   = var.smtp_host
    smtp_port   = var.smtp_port
    smtp_user   = var.smtp_user
    smtp_pass   = var.smtp_password
    smtp_sender = var.smtp_sender
  })

  user_data_replace_on_change = true

  lifecycle {
    ignore_changes = [
      ami,
      user_data,
      user_data_base64
    ]
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-instance" })
}

# ============================================
# Elastic IP
# ============================================
resource "aws_eip" "n8n" {
  domain = "vpc"
  tags   = merge(local.tags, { Name = "${local.name_prefix}-eip" })
}

resource "aws_eip_association" "n8n" {
  instance_id   = aws_instance.n8n.id
  allocation_id = aws_eip.n8n.id
}

# ============================================
# Route53 - registro A apuntando a la EIP
# ============================================
resource "aws_route53_record" "n8n" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.fqdn
  type    = "A"
  ttl     = 300
  records = [aws_eip.n8n.public_ip]
}

# ============================================
# EventBridge - Schedules de start/stop para ahorrar costo
# ============================================
resource "aws_iam_role" "eventbridge" {
  name_prefix = "${local.name_prefix}-eventbridge-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(local.tags, { Name = "${local.name_prefix}-eventbridge-role" })
}

resource "aws_iam_role_policy" "eventbridge_ssm" {
  role = aws_iam_role.eventbridge.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["ssm:StartAutomationExecution"]
        Resource = [
          "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}::automation-definition/AWS-StartEC2Instance:$DEFAULT",
          "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}::automation-definition/AWS-StopEC2Instance:$DEFAULT"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetAutomationExecution"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = aws_iam_role.eventbridge.arn
      }
    ]
  })
}

resource "aws_cloudwatch_event_rule" "stop_instance" {
  name                = "${local.name_prefix}-stop-schedule"
  schedule_expression = var.stop_schedule_cron
  description         = "Stop ${local.name_prefix} based on schedule"
  tags                = merge(local.tags, { Name = "${local.name_prefix}-stop-rule" })
}

resource "aws_cloudwatch_event_target" "stop_instance" {
  rule      = aws_cloudwatch_event_rule.stop_instance.name
  target_id = "Stop-${local.name_prefix}"
  arn       = "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}::automation-definition/AWS-StopEC2Instance:$DEFAULT"
  role_arn  = aws_iam_role.eventbridge.arn

  input = jsonencode({
    InstanceId = [aws_instance.n8n.id]
  })
}

resource "aws_cloudwatch_event_rule" "start_instance" {
  name                = "${local.name_prefix}-start-schedule"
  schedule_expression = var.start_schedule_cron
  description         = "Start ${local.name_prefix} based on schedule"
  tags                = merge(local.tags, { Name = "${local.name_prefix}-start-rule" })
}

resource "aws_cloudwatch_event_target" "start_instance" {
  rule      = aws_cloudwatch_event_rule.start_instance.name
  target_id = "Start-${local.name_prefix}"
  arn       = "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}::automation-definition/AWS-StartEC2Instance:$DEFAULT"
  role_arn  = aws_iam_role.eventbridge.arn

  input = jsonencode({
    InstanceId = [aws_instance.n8n.id]
  })
}
