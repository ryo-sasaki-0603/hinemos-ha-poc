locals {
  name = "${var.project}-${var.env}"
}

# RHEL9 AMI（Red Hat公式）
data "aws_ami" "rhel9" {
  owners      = ["309956199498"] # Red Hat
  most_recent = true
  filter {
    name   = "name"
    values = ["RHEL-9*HVM-*x86_64*"]
  }
}

# VPC & Subnet (Public)
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "${local.name}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags = { Name = "${local.name}-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.az
  map_public_ip_on_launch = true
  tags = { Name = "${local.name}-public-subnet" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${local.name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# SG (SSHのみ。必要に応じて8080等を許可)
resource "aws_security_group" "ec2" {
  name        = "${local.name}-ec2-sg"
  description = "SSH from my ip; egress all"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "http"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-ec2-sg" }
}

# IAM（Pacemaker用に最小限: EBS/ENI操作）
resource "aws_iam_role" "ec2_ha_role" {
  name               = "${local.name}-ec2-ha-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals { type = "Service", identifiers = ["ec2.amazonaws.com"] }
  }
}

data "aws_iam_policy_document" "ha_policy_doc" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "ec2:AttachVolume", "ec2:DetachVolume",
      "ec2:AttachNetworkInterface", "ec2:DetachNetworkInterface",
      "ec2:AssignPrivateIpAddresses", "ec2:UnassignPrivateIpAddresses",
      "ec2:AssociateAddress", "ec2:DisassociateAddress",
      "ec2:CreateTags", "ec2:DeleteTags"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ha_policy" {
  name   = "${local.name}-ha-policy"
  policy = data.aws_iam_policy_document.ha_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "attach" {
  role       = aws_iam_role.ec2_ha_role.name
  policy_arn = aws_iam_policy.ha_policy.arn
}

resource "aws_iam_instance_profile" "ec2_ha_profile" {
  name = "${local.name}-ec2-ha-profile"
  role = aws_iam_role.ec2_ha_role.name
}

# VIP用ENI（同一サブネット・同一AZ）
resource "aws_network_interface" "vip" {
  subnet_id       = aws_subnet.public.id
  private_ips     = [var.vip_private_ip]
  security_groups = [aws_security_group.ec2.id]
  tags = { Name = "${local.name}-eni-vip" }
}

# EC2: Hinemos Manager
resource "aws_instance" "hinemos" {
  ami                         = data.aws_ami.rhel9.id
  instance_type               = var.mgr_instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  key_name                    = var.key_name
  iam_instance_profile        = aws_iam_instance_profile.ec2_ha_profile.name

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  tags = { Name = "${local.name}-ec2-hinemos" }
}

# EC2: DBノード x2（同一AZ）
resource "aws_instance" "db201" {
  ami                    = data.aws_ami.rhel9.id
  instance_type          = var.db_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2_ha_profile.name

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  availability_zone = var.az
  tags = { Name = "${local.name}-ec2-db201" }
}

resource "aws_instance" "db202" {
  ami                    = data.aws_ami.rhel9.id
  instance_type          = var.db_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2_ha_profile.name

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  availability_zone = var.az
  tags = { Name = "${local.name}-ec2-db202" }
}

# 共有EBS（初期はdb201へ）
resource "aws_ebs_volume" "shared" {
  availability_zone = var.az
  size              = var.shared_ebs_size
  type              = "gp3"
  tags = { Name = "${local.name}-ebs-shared" }
}

resource "aws_volume_attachment" "shared_on_db201" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.shared.id
  instance_id = aws_instance.db201.id
}

# VIP ENIを初期はdb201へ
resource "aws_network_interface_attachment" "vip_on_db201" {
  instance_id          = aws_instance.db201.id
  network_interface_id = aws_network_interface.vip.id
  device_index         = 1
}

# Ansibleインベントリ生成
resource "local_file" "inventory" {
  filename = "${path.module}/../ansible/inventory.ini"
  content  = templatefile("${path.module}/templates/inventory.ini.tftpl", {
    hinemos_name   = "ec2-hinemos"
    hinemos_host   = aws_instance.hinemos.public_ip
    db201_name     = "ec2-db201"
    db202_name     = "ec2-db202"
    db201_pub      = aws_instance.db201.public_ip
    db202_pub      = aws_instance.db202.public_ip
    db201_priv     = aws_instance.db201.private_ip
    db202_priv     = aws_instance.db202.private_ip
    vip_ip         = var.vip_private_ip
    ansible_user   = "ec2-user" # RHEL公式AMIはec2-user
    ssh_key_path   = "~/.ssh/${var.key_name}.pem"
  })
}