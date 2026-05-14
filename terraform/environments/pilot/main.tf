# Workload root for Phase 1 Moodle stack. See modules/ for resource definitions.
module "network" {
  source = "../../modules/network"

  project_name                = var.project_name
  environment                 = var.environment
  vpc_cidr                    = var.vpc_cidr
  availability_zones          = var.availability_zones
  public_subnet_cidrs         = var.public_subnet_cidrs
  private_subnet_cidrs        = var.private_subnet_cidrs
  vpc_flow_log_retention_days = var.vpc_flow_log_retention_days
}

module "security" {
  source = "../../modules/security"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.network.vpc_id
}

module "data" {
  source = "../../modules/data"

  project_name                = var.project_name
  environment                 = var.environment
  db_subnet_ids               = module.network.private_subnet_ids
  db_sg_id                    = module.security.db_sg_id
  db_instance_class           = var.db_instance_class
  db_allocated_storage_gb     = var.db_allocated_storage_gb
  db_max_allocated_storage_gb = var.db_max_allocated_storage_gb
  db_engine_version           = var.db_engine_version
  db_backup_retention_days    = var.db_backup_retention_days
  db_master_username          = var.db_master_username
  db_master_password          = module.security.db_master_password
}

module "cache" {
  source = "../../modules/cache"

  project_name         = var.project_name
  environment          = var.environment
  cache_subnet_ids     = module.network.private_subnet_ids
  cache_sg_id          = module.security.cache_sg_id
  cache_node_type      = var.cache_node_type
  cache_engine_version = var.cache_engine_version
}

module "storage" {
  source = "../../modules/storage"

  project_name  = var.project_name
  environment   = var.environment
  efs_subnet_id = module.network.private_subnet_ids[0]
  # Phase 1 single-AZ choice expressed via list indexing.
  # private_subnet_ids = [AZ-a subnet, AZ-b subnet] from
  # modules/network. Index 0 = AZ-a (active AZ in Phase 1).
  # Phase 3 may add a second mount target wired to [1].
  efs_sg_id                 = module.security.efs_sg_id
  efs_throughput_mode       = var.efs_throughput_mode
  efs_backup_retention_days = var.efs_backup_retention_days
  backup_role_arn           = module.security.backup_role_arn
  ec2_role_arn              = module.security.ec2_role_arn
  # First consumer of the aws_backup role created in T-012.
}

module "compute" {
  source = "../../modules/compute"

  # Identity
  project_name = var.project_name
  environment  = var.environment

  # From workload root vars
  instance_type      = var.instance_type
  root_volume_gb     = var.root_volume_gb
  domain_name        = var.domain_name
  moodle_admin_email = var.moodle_admin_email
  aws_region         = var.aws_region

  # From module.network
  public_subnet_id = module.network.public_subnet_ids[0]
  # Phase 1 single-AZ - index 0 = AZ-a (active AZ). Phase 3 may
  # add a second instance wired to public_subnet_ids[1] under an
  # ASG/ALB topology.

  # From module.security
  web_sg_id                 = module.security.web_sg_id
  ec2_instance_profile_name = module.security.ec2_instance_profile_name
  db_secret_arn             = module.security.db_secret_arn
  admin_secret_arn          = module.security.admin_secret_arn

  # From module.data
  db_address  = module.data.db_address
  db_endpoint = module.data.db_endpoint
  db_port     = module.data.db_port

  # From module.cache
  cache_endpoint   = module.cache.cache_endpoint
  cache_port       = module.cache.cache_port
  cache_auth_token = module.cache.cache_auth_token
  # First consumer of cache_auth_token (created in T-015).
  # Sensitive value flows through to user-data via templatefile.

  # From module.storage
  efs_id = module.storage.efs_id
}

module "dns_cdn" {
  source = "../../modules/dns_cdn"

  # dns_cdn is the first module that requires an explicit providers
  # block. The us_east_1 alias is declared in versions.tf; the
  # module's configuration_aliases = [aws.us_east_1] requires this
  # explicit handoff - Terraform errors at plan time without it.
  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  project_name       = var.project_name
  environment        = var.environment
  domain_name        = var.domain_name
  origin_domain_name = module.compute.eip_public_dns
  dmarc_rua_address  = var.dmarc_rua_address
}

module "observability" {
  source = "../../modules/observability"

  project_name             = var.project_name
  environment              = var.environment
  alarm_email              = var.alarm_email
  log_retention_days       = var.log_retention_days
  domain_name              = var.domain_name
  enable_synthetics_canary = var.enable_synthetics_canary

  # Cross-module wiring: the three resource IDs used as CloudWatch alarm dimensions.
  instance_id            = module.compute.instance_id
  db_instance_identifier = module.data.db_id
  cache_cluster_id       = module.cache.cache_cluster_id
}
