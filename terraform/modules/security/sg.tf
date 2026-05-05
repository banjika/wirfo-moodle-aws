# --------------------------------------------------------------------------
# CloudFront origin-facing prefix list — used for web_sg ingress.
# Looked up by name so no hardcoded pl-* IDs cross region boundaries.
# --------------------------------------------------------------------------
data "aws_ec2_managed_prefix_list" "cloudfront_origin" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# --------------------------------------------------------------------------
# Security groups (no inline rules; egress = [] to override AWS default
# allow-all. Rules are separate resources to break SG-to-SG ref cycles.)
# --------------------------------------------------------------------------

resource "aws_security_group" "web" {
  name        = "${var.project_name}-${var.environment}-web-sg"
  description = "EC2 web tier — ingress from CloudFront only; egress to AWS APIs, db, cache, efs"
  vpc_id      = var.vpc_id

  # No inline rules; rules managed via aws_vpc_security_group_*_rule below.
  egress = []

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-web-sg"
  }
}

resource "aws_security_group" "db" {
  name        = "${var.project_name}-${var.environment}-db-sg"
  description = "RDS tier — ingress from web_sg only; default deny egress (RDS does not need outbound)"
  vpc_id      = var.vpc_id

  egress = []

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-db-sg"
  }
}

resource "aws_security_group" "cache" {
  name        = "${var.project_name}-${var.environment}-cache-sg"
  description = "ElastiCache Valkey tier — ingress from web_sg; default deny egress"
  vpc_id      = var.vpc_id

  egress = []

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-cache-sg"
  }
}

resource "aws_security_group" "efs" {
  name        = "${var.project_name}-${var.environment}-efs-sg"
  description = "EFS mount-target tier — ingress 2049 NFS-over-TLS from web_sg; default deny egress"
  vpc_id      = var.vpc_id

  egress = []

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-efs-sg"
  }
}

# --------------------------------------------------------------------------
# Ingress rules (5 total)
# --------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "web_https_from_cloudfront" {
  security_group_id = aws_security_group.web.id
  description       = "HTTPS from CloudFront origin-facing prefix list"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront_origin.id

  tags = {
    Name = "${var.project_name}-${var.environment}-web-ingress-443-cloudfront"
  }
}

# checkov:skip=CKV_AWS_260: source is CloudFront managed prefix list, not 0.0.0.0/0. CLAUDE.md hard rule #7.
resource "aws_vpc_security_group_ingress_rule" "web_http_from_cloudfront" {
  security_group_id = aws_security_group.web.id
  description       = "HTTP from CloudFront (origin redirect to HTTPS)"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront_origin.id

  tags = {
    Name = "${var.project_name}-${var.environment}-web-ingress-80-cloudfront"
  }
}

resource "aws_vpc_security_group_ingress_rule" "db_postgres_from_web" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL from web_sg"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.web.id

  tags = {
    Name = "${var.project_name}-${var.environment}-db-ingress-5432-web"
  }
}

resource "aws_vpc_security_group_ingress_rule" "cache_valkey_from_web" {
  security_group_id            = aws_security_group.cache.id
  description                  = "Valkey from web_sg"
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = aws_security_group.web.id

  tags = {
    Name = "${var.project_name}-${var.environment}-cache-ingress-6379-web"
  }
}

resource "aws_vpc_security_group_ingress_rule" "efs_nfs_from_web" {
  security_group_id            = aws_security_group.efs.id
  description                  = "NFS over TLS from web_sg"
  ip_protocol                  = "tcp"
  from_port                    = 2049
  to_port                      = 2049
  referenced_security_group_id = aws_security_group.web.id

  tags = {
    Name = "${var.project_name}-${var.environment}-efs-ingress-2049-web"
  }
}

# --------------------------------------------------------------------------
# Egress rules — web_sg only (7 total; other SGs have egress = [])
# TCP 443 and TCP 587 each split into IPv4 + IPv6 because
# aws_vpc_security_group_egress_rule accepts only one of cidr_ipv4/cidr_ipv6.
# --------------------------------------------------------------------------

resource "aws_vpc_security_group_egress_rule" "web_https_to_internet" {
  security_group_id = aws_security_group.web.id
  description       = "HTTPS to AWS APIs (SSM, SecretsManager, SES, CW), Ubuntu repos, GuardDuty agent — no NAT means direct egress"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "${var.project_name}-${var.environment}-web-egress-443-ipv4"
  }
}

resource "aws_vpc_security_group_egress_rule" "web_https_to_internet_v6" {
  security_group_id = aws_security_group.web.id
  description       = "HTTPS to AWS APIs (IPv6)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv6         = "::/0"

  tags = {
    Name = "${var.project_name}-${var.environment}-web-egress-443-ipv6"
  }
}

resource "aws_vpc_security_group_egress_rule" "web_smtps_to_ses" {
  security_group_id = aws_security_group.web.id
  description       = "SES SMTP submission"
  ip_protocol       = "tcp"
  from_port         = 587
  to_port           = 587
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "${var.project_name}-${var.environment}-web-egress-587-ipv4"
  }
}

resource "aws_vpc_security_group_egress_rule" "web_smtps_to_ses_v6" {
  security_group_id = aws_security_group.web.id
  description       = "SES SMTP submission (IPv6)"
  ip_protocol       = "tcp"
  from_port         = 587
  to_port           = 587
  cidr_ipv6         = "::/0"

  tags = {
    Name = "${var.project_name}-${var.environment}-web-egress-587-ipv6"
  }
}

resource "aws_vpc_security_group_egress_rule" "web_postgres_to_db" {
  security_group_id            = aws_security_group.web.id
  description                  = "PostgreSQL to db_sg"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.db.id

  tags = {
    Name = "${var.project_name}-${var.environment}-web-egress-5432-db"
  }
}

resource "aws_vpc_security_group_egress_rule" "web_valkey_to_cache" {
  security_group_id            = aws_security_group.web.id
  description                  = "Valkey to cache_sg"
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = aws_security_group.cache.id

  tags = {
    Name = "${var.project_name}-${var.environment}-web-egress-6379-cache"
  }
}

resource "aws_vpc_security_group_egress_rule" "web_nfs_to_efs" {
  security_group_id            = aws_security_group.web.id
  description                  = "NFS over TLS to efs_sg"
  ip_protocol                  = "tcp"
  from_port                    = 2049
  to_port                      = 2049
  referenced_security_group_id = aws_security_group.efs.id

  tags = {
    Name = "${var.project_name}-${var.environment}-web-egress-2049-efs"
  }
}
