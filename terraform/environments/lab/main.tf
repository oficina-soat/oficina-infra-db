data "aws_eks_cluster" "selected" {
  count = var.eks_cluster_name != null ? 1 : 0
  name  = var.eks_cluster_name
}

locals {
  eks_vpc_id = try(data.aws_eks_cluster.selected[0].vpc_config[0].vpc_id, null)
  eks_subnet_ids = try(
    data.aws_eks_cluster.selected[0].vpc_config[0].subnet_ids,
    [],
  )
  eks_cluster_security_group_ids = var.auto_allow_eks_cluster_security_group ? compact([
    try(data.aws_eks_cluster.selected[0].vpc_config[0].cluster_security_group_id, null),
  ]) : []

  resolved_vpc_id         = var.vpc_id != null ? var.vpc_id : local.eks_vpc_id
  resolved_subnet_ids     = length(var.subnet_ids) > 0 ? var.subnet_ids : local.eks_subnet_ids
  resolved_allowed_sg_ids = distinct(concat(var.allowed_security_group_ids, local.eks_cluster_security_group_ids))
}

check "network_inputs" {
  assert {
    condition     = local.resolved_vpc_id != null && length(local.resolved_subnet_ids) >= 2
    error_message = "Informe vpc_id e pelo menos duas subnet_ids, ou defina eks_cluster_name para descobrir a rede do cluster automaticamente."
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
