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
    condition     = length(var.allowed_cidr_blocks) > 0 || length(var.allowed_security_group_ids) > 0
    error_message = "Informe ao menos um CIDR ou security group autorizado a conectar no RDS."
  }
}
