variable "vpc_id" {
  type        = string
  description = "VPC onde o RDS sera provisionado."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Lista de sub-redes para o DB subnet group."

  validation {
    condition     = length(var.subnet_ids) >= 2
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
    condition     = length(var.allowed_cidr_blocks) > 0 || length(var.allowed_security_group_ids) > 0
    error_message = "Informe ao menos um CIDR ou security group autorizado a conectar no RDS."
  }

  validation {
    condition     = !contains(var.allowed_cidr_blocks, "0.0.0.0/0")
    error_message = "Nao exponha o banco para 0.0.0.0/0."
  }
}
