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
