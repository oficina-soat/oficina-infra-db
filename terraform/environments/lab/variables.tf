variable "region" {
  type    = string
  default = "us-east-1"
}

variable "shared_infra_name" {
  type        = string
  description = "Prefixo compartilhado de nomes do laboratorio. Quando nulo, reaproveita eks_cluster_name e cai para eks-lab."
  default     = null
  nullable    = true
}

variable "eks_cluster_name" {
  type        = string
  description = "Nome do cluster EKS compartilhado do laboratorio. Quando informado, tenta liberar acesso ao banco para os security groups tagueados desse cluster."
  default     = "eks-lab"

  validation {
    condition     = trimspace(var.eks_cluster_name) != ""
    error_message = "eks_cluster_name nao pode ser vazio."
  }
}

variable "auto_allow_eks_cluster_security_group" {
  type        = bool
  description = "Quando true, adiciona automaticamente os security groups do cluster EKS descobertos por tag como origem permitida para o banco."
  default     = true
}

variable "create_network_if_missing" {
  type        = bool
  description = "Quando true, cria uma VPC dedicada com duas subnets publicas se nenhuma rede compartilhada existente for encontrada."
  default     = true
}

variable "network_vpc_cidr" {
  type        = string
  description = "CIDR da VPC criada automaticamente quando create_network_if_missing=true."
  default     = "10.0.0.0/16"
}

variable "azs" {
  type        = list(string)
  description = "Availability zones usadas pela rede criada automaticamente. Se vazio, usa duas zonas derivadas da regiao."
  default     = []

  validation {
    condition     = length(var.azs) == 0 || length(var.azs) >= 2
    error_message = "Informe pelo menos duas availability zones ou deixe vazio para usar o padrao."
  }
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs das subnets publicas quando a rede deste projeto precisar ser criada."
  default     = ["10.0.0.0/20", "10.0.16.0/20"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "Informe pelo menos dois CIDRs de subnets publicas."
  }
}

variable "db_identifier" {
  type        = string
  description = "Identificador unico da instancia RDS."
  default     = "oficina-postgres-lab"
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
  description = "Expose a instancia publicamente. Default true no laboratorio."
  default     = true
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

variable "vpc_id" {
  type        = string
  description = "VPC onde o RDS sera provisionado. Se omitido, o projeto tenta reutilizar <shared_infra_name>-vpc e, se ainda nao existir, cria uma rede nova."
  default     = null
  nullable    = true
}

variable "subnet_ids" {
  type        = list(string)
  description = "Lista de sub-redes para o DB subnet group. Se vazia, o projeto tenta reutilizar as subnets da VPC compartilhada ou criar as proprias."
  default     = []

  validation {
    condition     = length(var.subnet_ids) == 0 || length(var.subnet_ids) >= 2
    error_message = "Informe pelo menos duas sub-redes para o subnet group do RDS."
  }
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "Security groups autorizados a acessar a porta 5432 do RDS."
  default     = []
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "CIDRs autorizados a acessar a porta 5432 do RDS."
  default     = []

  validation {
    condition     = !contains(var.allowed_cidr_blocks, "0.0.0.0/0")
    error_message = "Nao exponha o banco para 0.0.0.0/0."
  }
}

variable "storage_kms_key_id" {
  type        = string
  description = "KMS key para criptografia do storage do RDS. Se null, usa a chave gerenciada pela AWS."
  default     = null
}

variable "create_terraform_shared_data_bucket" {
  type        = bool
  description = "Quando true, cria o bucket S3 de dados compartilhados do Terraform caso ele precise ser gerenciado por este state."
  default     = true
}

variable "terraform_shared_data_bucket_name" {
  type        = string
  description = "Nome do bucket S3 compartilhado. Se nulo, o nome e derivado de shared_infra_name, conta e regiao."
  default     = null
  nullable    = true
}

variable "terraform_shared_data_bucket_force_destroy" {
  type        = bool
  description = "Quando true, permite destruir o bucket compartilhado mesmo com objetos."
  default     = false
}

variable "master_user_secret_kms_key_id" {
  type        = string
  description = "KMS key da secret gerenciada do usuario master no Secrets Manager."
  default     = null
}

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

variable "ca_cert_identifier" {
  type        = string
  description = "CA certificate identifier do RDS. Se null, a AWS escolhe o padrao."
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

variable "tags" {
  type        = map(string)
  description = "Tags adicionais para os recursos."
  default     = {}
}
