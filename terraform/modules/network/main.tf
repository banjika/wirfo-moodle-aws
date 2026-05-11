locals {
  # Map keyed on "${az}-${tier}" → subnet attributes. Public subnets get IPv6
  # /64 indexes 0..N-1; private subnets get indexes 10..10+N-1, leaving room
  # for future public-subnet expansion without renumbering private subnets.
  subnets = merge(
    {
      for idx, az in var.availability_zones :
      "${az}-public" => {
        az         = az
        tier       = "public"
        cidr       = var.public_subnet_cidrs[idx]
        ipv6_index = idx
      }
    },
    {
      for idx, az in var.availability_zones :
      "${az}-private" => {
        az         = az
        tier       = "private"
        cidr       = var.private_subnet_cidrs[idx]
        ipv6_index = idx + 10
      }
    },
  )
}

resource "aws_vpc" "main" {
  cidr_block                       = var.vpc_cidr
  assign_generated_ipv6_cidr_block = true
  enable_dns_hostnames             = true
  enable_dns_support               = true

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc"
  }
}

# Public subnets explicitly auto-assign public IPs per CLAUDE.md hard rule #1
# (no NAT Gateway). The compute module in T-018 places EC2 only in public subnets.
#tfsec:ignore:aws-ec2-no-public-ip-subnet
resource "aws_subnet" "main" {
  for_each = local.subnets

  vpc_id                          = aws_vpc.main.id
  availability_zone               = each.value.az
  cidr_block                      = each.value.cidr
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, each.value.ipv6_index)
  assign_ipv6_address_on_creation = true
  map_public_ip_on_launch         = each.value.tier == "public"

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.value.tier}-${each.value.az}"
    Tier = each.value.tier
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-igw"
  }
}

resource "aws_egress_only_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-eigw"
  }
}

# Separate aws_route resources are used rather than inline route blocks inside
# aws_route_table. Inline routes are deprecated and the two forms must not be mixed.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-rt-public"
  }
}

resource "aws_route" "public_v4_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route" "public_v6_default" {
  route_table_id              = aws_route_table.public.id
  destination_ipv6_cidr_block = "::/0"
  gateway_id                  = aws_internet_gateway.main.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-rt-private"
  }
}

# No IPv4 default route - enforces no NAT Gateway (CLAUDE.md hard rule #1).
# IPv6 egress via EIGW is wired now for Phase 3 forward-compat.
resource "aws_route" "private_v6_default" {
  route_table_id              = aws_route_table.private.id
  destination_ipv6_cidr_block = "::/0"
  egress_only_gateway_id      = aws_egress_only_internet_gateway.main.id
}

resource "aws_route_table_association" "main" {
  for_each = local.subnets

  subnet_id      = aws_subnet.main[each.key].id
  route_table_id = each.value.tier == "public" ? aws_route_table.public.id : aws_route_table.private.id
}

# Defensively empty the VPC's implicit main route table so any subnet not
# explicitly associated with public/private route tables cannot route anywhere.
resource "aws_default_route_table" "default" {
  default_route_table_id = aws_vpc.main.default_route_table_id

  tags = {
    Name = "${var.project_name}-${var.environment}-rt-default-empty"
  }
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
  # No ingress / egress blocks - empty by design.
  # CLAUDE.md hard rule #8: internal traffic uses SG-to-SG references via
  # named SGs in modules/security. This default SG must remain empty so any
  # accidentally-unassigned resource cannot communicate.
  tags = {
    Name = "${var.project_name}-${var.environment}-sg-default-empty"
  }
}
