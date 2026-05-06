data "aws_ami" "ubuntu" {
  owners      = ["099720109477"] # Canonical
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-jammy-22.04-arm64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Phase 1: EC2 in public subnet with EIP — no NAT Gateway (CLAUDE.md hard rule #1).
# Web SG ingress is restricted to the CloudFront origin-facing prefix list (T-011);
# admin access is via SSM Session Manager only — no SSH, no key pair (CLAUDE.md hard rule #6).
# Phase 3 moves EC2 behind ALB into private subnets.
# Phase 1 cost stance: basic 5-minute monitoring is sufficient per requirements §6.
# CloudWatch Agent (T-022) provides 1-minute app-level metrics.
#checkov:skip=CKV_AWS_88: Phase 1 EC2 in public subnet with EIP — no NAT Gateway per CLAUDE.md hard rule #1. Web SG ingress restricted to CloudFront prefix list (T-011); admin via SSM only (hard rule #6). Phase 3 moves EC2 behind ALB into private subnets.
#checkov:skip=CKV_AWS_126: Phase 1 cost stance per requirements §6 — basic 5-minute monitoring sufficient. CloudWatch Agent (T-022) provides 1-minute app-level metrics.
resource "aws_instance" "moodle" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [var.web_sg_id]
  iam_instance_profile        = var.ec2_instance_profile_name
  associate_public_ip_address = true
  # Required: EC2 is in a public subnet (CLAUDE.md hard rule #1 — no NAT).
  # EIP attaches after instance creation; the auto-assigned IP is superseded by the EIP.

  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    aws_region         = var.aws_region
    domain_name        = var.domain_name
    moodle_admin_email = var.moodle_admin_email
    db_endpoint        = var.db_endpoint
    db_port            = var.db_port
    db_secret_arn      = var.db_secret_arn
    cache_endpoint     = var.cache_endpoint
    cache_port         = var.cache_port
    cache_auth_token   = var.cache_auth_token
    admin_secret_arn   = var.admin_secret_arn
    efs_id             = var.efs_id
  })

  user_data_replace_on_change = true
  # User-data runs only at first boot; any change must force instance replacement.

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_gb
    encrypted   = true
    kms_key_id  = null
    # Explicit null — uses aws/ebs default key per CLAUDE.md hard rule #3 (no CMK in Phase 1).
    delete_on_termination = true

    tags = {
      Name = "${var.project_name}-${var.environment}-moodle-root"
    }
  }

  metadata_options {
    http_tokens = "required"
    # IMDSv2 required — defence-in-depth for SSRF (CLAUDE.md security baseline).
    http_put_response_hop_limit = 1
    # Hop limit of 1 prevents containers/processes from querying IMDS on behalf of attackers.
    http_endpoint = "enabled"
  }

  ebs_optimized = true
  # Always-on for Graviton (t4g) instances at no extra cost; explicit here so the
  # setting is preserved if the instance_type variable is ever changed.

  monitoring = false
  # Phase 1 cost stance: basic 5-minute monitoring is sufficient (requirements §6).
  # Detailed monitoring costs $2.10/instance/month. CloudWatch Agent (T-022) covers
  # 1-minute app-level metrics at no extra EC2 charge.

  tags = {
    Name = "${var.project_name}-${var.environment}-moodle"
  }

  lifecycle {
    ignore_changes = [
      ami,
      # AMI data source resolves to "most_recent" Canonical Ubuntu image. Without
      # ignore_changes, every plan shows a diff when Canonical releases a new image (weekly).
      # Phase 1 accepts the lag; unattended-upgrades patches the running kernel.
      # AMI refresh is manual: remove ignore_changes, plan, apply, restore.
    ]
  }
}

resource "aws_eip" "moodle" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-moodle-eip"
  }
}

resource "aws_eip_association" "moodle" {
  instance_id   = aws_instance.moodle.id
  allocation_id = aws_eip.moodle.id
}
