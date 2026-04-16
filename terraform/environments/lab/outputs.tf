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

output "db_subnet_group_name" {
  value = module.rds_postgres.db_subnet_group_name
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

output "vpc_id" {
  value = local.resolved_vpc_id
}

output "subnet_ids" {
  value = local.resolved_subnet_ids
}

output "shared_infra_name" {
  value = local.shared_infra_name
}

output "terraform_shared_data_bucket_name" {
  value = try(module.terraform_shared_data_bucket[0].bucket_name, null)
}

output "terraform_shared_data_bucket_arn" {
  value = try(module.terraform_shared_data_bucket[0].bucket_arn, null)
}

output "network_managed_by_terraform" {
  value = local.create_network
}

output "terraform_shared_data_bucket_managed_by_terraform" {
  value = var.create_terraform_shared_data_bucket
}
