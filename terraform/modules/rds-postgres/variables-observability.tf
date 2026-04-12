variable "monitoring_interval" {
  type        = number
  description = "Intervalo em segundos do Enhanced Monitoring."
  default     = 0

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "Use um intervalo valido do Enhanced Monitoring: 0, 1, 5, 10, 15, 30 ou 60."
  }
}

variable "enabled_cloudwatch_logs_exports" {
  type        = list(string)
  description = "Logs exportados do PostgreSQL para CloudWatch."
  default     = []

  validation {
    condition = alltrue([
      for log_type in var.enabled_cloudwatch_logs_exports :
      contains(["postgresql", "upgrade", "iam-db-auth-error"], log_type)
    ])
    error_message = "Tipos de log invalidos para PostgreSQL."
  }
}

variable "cloudwatch_log_retention_in_days" {
  type        = number
  description = "Retencao dos log groups do CloudWatch."
  default     = 7
}

variable "cloudwatch_log_group_kms_key_id" {
  type        = string
  description = "KMS key para os log groups do CloudWatch. Se null, usa a chave padrao do servico."
  default     = null
}

variable "performance_insights_enabled" {
  type        = bool
  description = "Habilita Performance Insights."
  default     = false
}

variable "performance_insights_retention_period" {
  type        = number
  description = "Retencao em dias do Performance Insights."
  default     = 7

  validation {
    condition     = contains([7, 731], var.performance_insights_retention_period)
    error_message = "Use 7 ou 731 dias de retencao no Performance Insights."
  }
}

variable "performance_insights_kms_key_id" {
  type        = string
  description = "KMS key do Performance Insights. Se null, usa a chave padrao do servico."
  default     = null
}

variable "log_min_duration_statement_ms" {
  type        = number
  description = "Threshold em milissegundos para logar queries lentas."
  default     = 1000

  validation {
    condition     = var.log_min_duration_statement_ms >= 0
    error_message = "log_min_duration_statement_ms deve ser maior ou igual a zero."
  }
}

variable "alarm_actions" {
  type        = list(string)
  description = "Lista de ARNs acionados quando um alarme entra em estado ALARM."
  default     = []
}

variable "ok_actions" {
  type        = list(string)
  description = "Lista de ARNs acionados quando um alarme volta para OK."
  default     = []
}

variable "create_alarms" {
  type        = bool
  description = "Cria alarmes CloudWatch. Default false para manter custo minimo em laboratorio."
  default     = false
}

variable "cpu_utilization_alarm_threshold" {
  type        = number
  description = "Threshold percentual do alarme de CPU."
  default     = 80

  validation {
    condition     = var.cpu_utilization_alarm_threshold > 0 && var.cpu_utilization_alarm_threshold <= 100
    error_message = "cpu_utilization_alarm_threshold deve estar entre 0 e 100."
  }
}

variable "free_storage_space_alarm_threshold_bytes" {
  type        = number
  description = "Threshold em bytes do alarme de espaco livre."
  default     = 5368709120
}

variable "freeable_memory_alarm_threshold_bytes" {
  type        = number
  description = "Threshold em bytes do alarme de memoria livre."
  default     = 268435456
}
