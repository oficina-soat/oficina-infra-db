data "aws_caller_identity" "current" {}

data "aws_vpcs" "shared" {
  count = var.vpc_id == null ? 1 : 0

  tags = {
    Name = "${local.shared_infra_name}-vpc"
  }
}

data "aws_subnets" "shared" {
  count = var.vpc_id == null && length(var.subnet_ids) == 0 && local.existing_shared_vpc_id != null ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [local.existing_shared_vpc_id]
  }
}

data "aws_security_groups" "eks_cluster" {
  count = var.auto_allow_eks_cluster_security_group && local.preexisting_vpc_id != null && local.resolved_eks_cluster_name != null ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [local.preexisting_vpc_id]
  }

  filter {
    name   = "tag:aws:eks:cluster-name"
    values = [local.resolved_eks_cluster_name]
  }
}

locals {
  shared_infra_name = coalesce(var.shared_infra_name, var.eks_cluster_name, "eks-lab")
  resolved_eks_cluster_name = coalesce(
    var.eks_cluster_name,
    var.shared_infra_name,
    "eks-lab",
  )
  azs                     = length(var.azs) > 0 ? slice(var.azs, 0, 2) : ["${var.region}a", "${var.region}b"]
  existing_shared_vpc_ids = try(data.aws_vpcs.shared[0].ids, [])
  existing_shared_vpc_id  = length(local.existing_shared_vpc_ids) == 1 ? local.existing_shared_vpc_ids[0] : null
  preexisting_vpc_id      = var.vpc_id != null ? var.vpc_id : local.existing_shared_vpc_id
  create_network          = var.vpc_id == null && local.existing_shared_vpc_id == null && var.create_network_if_missing
  discovered_subnet_ids   = try(data.aws_subnets.shared[0].ids, [])
  eks_cluster_security_group_ids = var.auto_allow_eks_cluster_security_group ? try(
    data.aws_security_groups.eks_cluster[0].ids,
    [],
  ) : []
  resolved_vpc_id = coalesce(
    var.vpc_id,
    local.existing_shared_vpc_id,
    try(module.network[0].vpc_id, null),
  )
  resolved_subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : (
    length(local.discovered_subnet_ids) > 0 ? local.discovered_subnet_ids : try(module.network[0].public_subnet_ids, [])
  )
  resolved_allowed_sg_ids = distinct(concat(var.allowed_security_group_ids, local.eks_cluster_security_group_ids))
  terraform_shared_data_bucket_name = coalesce(
    var.terraform_shared_data_bucket_name,
    "tf-shared-${local.shared_infra_name}-${data.aws_caller_identity.current.account_id}-${var.region}",
  )
}

module "network" {
  count  = local.create_network ? 1 : 0
  source = "../../modules/network"

  name                = local.shared_infra_name
  cluster_name        = local.resolved_eks_cluster_name
  vpc_cidr            = var.network_vpc_cidr
  azs                 = local.azs
  public_subnet_cidrs = var.public_subnet_cidrs
}

module "terraform_shared_data_bucket" {
  count  = var.create_terraform_shared_data_bucket ? 1 : 0
  source = "../../modules/terraform_shared_data_bucket"

  bucket_name   = local.terraform_shared_data_bucket_name
  force_destroy = var.terraform_shared_data_bucket_force_destroy
}

check "network_inputs" {
  assert {
    condition     = local.resolved_vpc_id != null && length(local.resolved_subnet_ids) >= 2
    error_message = "Informe vpc_id e pelo menos duas subnet_ids, reutilize uma VPC nomeada como <shared_infra_name>-vpc, ou mantenha create_network_if_missing=true para criar a rede automaticamente."
  }
}

check "storage_inputs" {
  assert {
    condition     = var.max_allocated_storage >= var.allocated_storage
    error_message = "max_allocated_storage deve ser maior ou igual a allocated_storage."
  }
}

check "final_snapshot_inputs" {
  assert {
    condition     = var.skip_final_snapshot || var.final_snapshot_identifier != null
    error_message = "Informe final_snapshot_identifier quando skip_final_snapshot=false."
  }
}

check "database_access_inputs" {
  assert {
    condition     = length(var.allowed_cidr_blocks) > 0 || length(local.resolved_allowed_sg_ids) > 0
    error_message = "Informe allowed_cidr_blocks, allowed_security_group_ids, ou use eks_cluster_name com auto_allow_eks_cluster_security_group=true."
  }
}

check "shared_vpc_uniqueness" {
  assert {
    condition     = length(local.existing_shared_vpc_ids) <= 1
    error_message = "Mais de uma VPC com o nome esperado foi encontrada. Ajuste shared_infra_name ou informe vpc_id explicitamente."
  }
}

module "rds_postgres" {
  source = "../../modules/rds-postgres"

  db_identifier                            = var.db_identifier
  db_name                                  = var.db_name
  db_username                              = var.db_username
  instance_class                           = var.instance_class
  engine_version                           = var.engine_version
  allocated_storage                        = var.allocated_storage
  max_allocated_storage                    = var.max_allocated_storage
  storage_type                             = var.storage_type
  multi_az                                 = var.multi_az
  backup_retention_period                  = var.backup_retention_period
  backup_window                            = var.backup_window
  maintenance_window                       = var.maintenance_window
  publicly_accessible                      = var.publicly_accessible
  apply_immediately                        = var.apply_immediately
  deletion_protection                      = var.deletion_protection
  skip_final_snapshot                      = var.skip_final_snapshot
  final_snapshot_identifier                = var.final_snapshot_identifier
  vpc_id                                   = local.resolved_vpc_id
  subnet_ids                               = local.resolved_subnet_ids
  allowed_security_group_ids               = local.resolved_allowed_sg_ids
  allowed_cidr_blocks                      = var.allowed_cidr_blocks
  storage_kms_key_id                       = var.storage_kms_key_id
  master_user_secret_kms_key_id            = var.master_user_secret_kms_key_id
  monitoring_interval                      = var.monitoring_interval
  enabled_cloudwatch_logs_exports          = var.enabled_cloudwatch_logs_exports
  cloudwatch_log_retention_in_days         = var.cloudwatch_log_retention_in_days
  cloudwatch_log_group_kms_key_id          = var.cloudwatch_log_group_kms_key_id
  performance_insights_enabled             = var.performance_insights_enabled
  performance_insights_retention_period    = var.performance_insights_retention_period
  performance_insights_kms_key_id          = var.performance_insights_kms_key_id
  ca_cert_identifier                       = var.ca_cert_identifier
  log_min_duration_statement_ms            = var.log_min_duration_statement_ms
  alarm_actions                            = var.alarm_actions
  ok_actions                               = var.ok_actions
  create_alarms                            = var.create_alarms
  cpu_utilization_alarm_threshold          = var.cpu_utilization_alarm_threshold
  free_storage_space_alarm_threshold_bytes = var.free_storage_space_alarm_threshold_bytes
  freeable_memory_alarm_threshold_bytes    = var.freeable_memory_alarm_threshold_bytes
  tags                                     = var.tags
}
