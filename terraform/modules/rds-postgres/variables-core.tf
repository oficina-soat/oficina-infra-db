variable "db_identifier" {
  type        = string
  description = "Identificador unico da instancia RDS."
  default     = "oficina-postgres"
}

variable "db_name" {
  type        = string
  description = "Nome inicial do banco da aplicacao."
  default     = "app"
}

variable "db_username" {
  type        = string
  description = "Usuario administrador inicial do banco. Nao deve ser reutilizado pela aplicacao."
  default     = "oficina_master"
}

variable "instance_class" {
  type        = string
  description = "Classe da instancia RDS. Defaults alinhados ao ADR: db.t4g.micro ou db.t4g.small."
  default     = "db.t4g.micro"

  validation {
    condition     = contains(["db.t4g.micro", "db.t4g.small"], var.instance_class)
    error_message = "Use db.t4g.micro ou db.t4g.small para manter o provisionamento alinhado ao ADR."
  }
}

variable "engine_version" {
  type        = string
  description = "Versao major do PostgreSQL gerenciado."
  default     = "16"
}

variable "allocated_storage" {
  type        = number
  description = "Storage inicial em GB."
  default     = 20
}

variable "max_allocated_storage" {
  type        = number
  description = "Limite maximo em GB para autoscaling de storage."
  default     = 40
}

variable "storage_type" {
  type        = string
  description = "Tipo do storage do RDS."
  default     = "gp3"

  validation {
    condition     = var.storage_type == "gp3"
    error_message = "O ADR definiu gp3 como storage padrao."
  }
}

variable "multi_az" {
  type        = bool
  description = "Habilita Multi-AZ para alta disponibilidade. Em laboratorio, o default permanece false por custo."
  default     = false
}

variable "backup_retention_period" {
  type        = number
  description = "Dias de retencao de backup automatico."
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 7 && var.backup_retention_period <= 35
    error_message = "Use entre 7 e 35 dias de retencao para um baseline de producao."
  }
}

variable "backup_window" {
  type        = string
  description = "Janela diaria de backup no formato hh24:mi-hh24:mi em UTC."
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  type        = string
  description = "Janela semanal de manutencao no formato ddd:hh24:mi-ddd:hh24:mi em UTC."
  default     = "sun:04:00-sun:05:00"
}

variable "publicly_accessible" {
  type        = bool
  description = "Expose a instancia publicamente. Default false."
  default     = false
}

variable "apply_immediately" {
  type        = bool
  description = "Aplica alteracoes imediatamente. Em producao, mantenha false."
  default     = false
}

variable "deletion_protection" {
  type        = bool
  description = "Protecao contra delete acidental."
  default     = true
}

variable "skip_final_snapshot" {
  type        = bool
  description = "Pula snapshot final ao destruir. Em producao, mantenha false."
  default     = false
}

variable "final_snapshot_identifier" {
  type        = string
  description = "Identificador do snapshot final quando skip_final_snapshot=false."
  default     = null
}

variable "storage_kms_key_id" {
  type        = string
  description = "KMS key para criptografia do storage do RDS. Se null, usa a chave gerenciada pela AWS."
  default     = null
}

variable "master_user_secret_kms_key_id" {
  type        = string
  description = "KMS key da secret gerenciada do usuario master no Secrets Manager."
  default     = null
}

variable "ca_cert_identifier" {
  type        = string
  description = "CA certificate identifier do RDS. Se null, a AWS escolhe o padrao."
  default     = null
}
