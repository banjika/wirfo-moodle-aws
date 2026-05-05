output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "IPv4 CIDR block of the VPC."
  value       = aws_vpc.main.cidr_block
}

output "vpc_ipv6_cidr_block" {
  description = "Amazon-provided IPv6 /56 CIDR block of the VPC; useful for security group rules."
  value       = aws_vpc.main.ipv6_cidr_block
}

# Ordered to match availability_zones[i] so callers can rely on positional indexing
# (e.g. public_subnet_ids[0] is always the AZ-a subnet used by EC2 in T-018).
output "public_subnet_ids" {
  description = "Public subnet IDs in availability_zones order."
  value = [
    for az in var.availability_zones :
    aws_subnet.main["${az}-public"].id
  ]
}

output "private_subnet_ids" {
  description = "Private subnet IDs in availability_zones order."
  value = [
    for az in var.availability_zones :
    aws_subnet.main["${az}-private"].id
  ]
}

output "igw_id" {
  description = "ID of the Internet Gateway."
  value       = aws_internet_gateway.main.id
}

output "eigw_id" {
  description = "ID of the Egress-Only Internet Gateway."
  value       = aws_egress_only_internet_gateway.main.id
}
