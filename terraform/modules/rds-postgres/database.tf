resource "aws_db_parameter_group" "this" {
  name        = "${local.name_prefix}-pg"
  family      = "postgres${local.engine_major_version}"
  description = "Parametros PostgreSQL de producao para ${var.db_identifier}"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "password_encryption"
    value        = "scram-sha-256"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "log_connections"
    value = "0"
  }

  parameter {
    name  = "log_disconnections"
    value = "0"
  }

  parameter {
    name  = "log_lock_waits"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = tostring(var.log_min_duration_statement_ms)
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-pg"
  })
}

resource "aws_db_instance" "this" {
  identifier                            = var.db_identifier
  engine                                = "postgres"
  engine_version                        = var.engine_version
  instance_class                        = var.instance_class
  allocated_storage                     = var.allocated_storage
  max_allocated_storage                 = var.max_allocated_storage
  storage_type                          = var.storage_type
  storage_encrypted                     = true
  kms_key_id                            = var.storage_kms_key_id
  db_name                               = var.db_name
  username                              = var.db_username
  manage_master_user_password           = true
  master_user_secret_kms_key_id         = var.master_user_secret_kms_key_id
  port                                  = local.db_port
  db_subnet_group_name                  = aws_db_subnet_group.this.name
  vpc_security_group_ids                = [aws_security_group.this.id]
  parameter_group_name                  = aws_db_parameter_group.this.name
  backup_retention_period               = var.backup_retention_period
  backup_window                         = var.backup_window
  maintenance_window                    = var.maintenance_window
  multi_az                              = var.multi_az
  publicly_accessible                   = var.publicly_accessible
  apply_immediately                     = var.apply_immediately
  deletion_protection                   = var.deletion_protection
  delete_automated_backups              = false
  skip_final_snapshot                   = var.skip_final_snapshot
  final_snapshot_identifier             = var.skip_final_snapshot ? null : var.final_snapshot_identifier
  iam_database_authentication_enabled   = false
  allow_major_version_upgrade           = false
  auto_minor_version_upgrade            = true
  copy_tags_to_snapshot                 = true
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = var.monitoring_interval > 0 ? aws_iam_role.rds_enhanced_monitoring[0].arn : null
  enabled_cloudwatch_logs_exports       = var.enabled_cloudwatch_logs_exports
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_kms_key_id       = var.performance_insights_kms_key_id
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null
  ca_cert_identifier                    = var.ca_cert_identifier

  tags = merge(local.common_tags, {
    Name = var.db_identifier
  })

  depends_on = [
    aws_cloudwatch_log_group.this,
    aws_iam_role_policy_attachment.rds_enhanced_monitoring,
  ]
}
