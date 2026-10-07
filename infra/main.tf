terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "income-lab"
      ManagedBy = "Terraform"
    }
  }
}

resource "aws_s3_bucket" "lab" {
  bucket        = var.bucket_name
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "lab" {
  bucket = aws_s3_bucket.lab.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lab" {
  bucket = aws_s3_bucket.lab.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "https_only" {
  bucket = aws_s3_bucket.lab.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.lab.arn,
        "${aws_s3_bucket.lab.arn}/*"
      ]
      Condition = {
        Bool = {
          "aws:SecureTransport" = "false"
        }
      }
    }]
  })
}

resource "aws_iam_role" "ec2" {
  name_prefix = "income-api-"

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
}

resource "aws_iam_role_policy" "ec2_model" {
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.lab.arn}/artifacts/current/model.joblib"
    }]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name_prefix = "income-api-"
  role        = aws_iam_role.ec2.name
}

data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}

resource "aws_key_pair" "deploy" {
  key_name_prefix = "income-deploy-"
  public_key      = trimspace(file(pathexpand(var.ssh_public_key_path)))
}

resource "aws_security_group" "api" {
  name_prefix = "income-api-"
  description = "SSH va API tu may quan tri"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "Inference API"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "api" {
  ami                         = data.aws_ssm_parameter.ubuntu.value
  instance_type               = "t3.small"
  subnet_id                   = var.subnet_id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.api.id]
  key_name                    = aws_key_pair.deploy.key_name
  iam_instance_profile        = aws_iam_instance_profile.ec2.name

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 16
    encrypted   = true
  }

  credit_specification {
    cpu_credits = "standard"
  }

  user_data = templatefile("${path.module}/user_data.sh", {
    bucket_name = aws_s3_bucket.lab.id
    region      = var.region
  })

  user_data_replace_on_change = true

  depends_on = [aws_iam_role_policy.ec2_model]

  tags = {
    Name = "income-api"
  }
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.github_oidc_provider_arn == "" ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

locals {
  github_oidc_arn = (
    var.github_oidc_provider_arn != ""
    ? var.github_oidc_provider_arn
    : aws_iam_openid_connect_provider.github[0].arn
  )
}

resource "aws_iam_role" "github" {
  name_prefix = "income-github-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = local.github_oidc_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = var.github_oidc_subject != "" ? var.github_oidc_subject : "repo:${var.github_repo}:ref:refs/heads/main"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github_storage" {
  role = aws_iam_role.github.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.lab.arn
        Condition = {
          StringLike = {
            "s3:prefix" = ["dvc", "dvc/*"]
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.lab.arn}/dvc/*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.lab.arn}/artifacts/current/model.joblib"
      }
    ]
  })
}

# Allow the release job to open SSH for its own IP and remove that rule afterward.
resource "aws_iam_role_policy" "github_deploy_network" {
  role = aws_iam_role.github.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupIngress"
      ]
      Resource = aws_security_group.api.arn
    }]
  })
}
