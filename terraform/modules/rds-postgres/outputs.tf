output "db_instance_identifier" {
  value = aws_db_instance.this.identifier
}

output "db_endpoint" {
  value = aws_db_instance.this.address
}

output "db_port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "db_username" {
  value = aws_db_instance.this.username
}

output "db_security_group_id" {
  value = aws_security_group.this.id
}

output "db_subnet_group_name" {
  value = aws_db_subnet_group.this.name
}

output "db_parameter_group_name" {
  value = aws_db_parameter_group.this.name
}

output "db_master_user_secret_arn" {
  value = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "db_cloudwatch_log_group_names" {
  value = [for log_group in aws_cloudwatch_log_group.this : log_group.name]
}

output "db_alarm_names" {
  value = var.create_alarms ? [
    aws_cloudwatch_metric_alarm.cpu_high[0].alarm_name,
    aws_cloudwatch_metric_alarm.free_storage_low[0].alarm_name,
    aws_cloudwatch_metric_alarm.freeable_memory_low[0].alarm_name,
  ] : []
}
