output "db_instance_identifier" {
  value = module.rds_postgres.db_instance_identifier
}

output "db_endpoint" {
  value = module.rds_postgres.db_endpoint
}

output "db_port" {
  value = module.rds_postgres.db_port
}

output "db_name" {
  value = module.rds_postgres.db_name
}

output "db_username" {
  value = module.rds_postgres.db_username
}

output "db_security_group_id" {
  value = module.rds_postgres.db_security_group_id
}

output "db_parameter_group_name" {
  value = module.rds_postgres.db_parameter_group_name
}

output "db_master_user_secret_arn" {
  value = module.rds_postgres.db_master_user_secret_arn
}

output "db_cloudwatch_log_group_names" {
  value = module.rds_postgres.db_cloudwatch_log_group_names
}

output "db_alarm_names" {
  value = module.rds_postgres.db_alarm_names
}
