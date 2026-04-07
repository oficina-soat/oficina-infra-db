locals {
  name_prefix          = var.db_identifier
  db_port              = 5432
  engine_major_version = split(".", var.engine_version)[0]
  common_tags = merge(
    {
      Project   = "oficina"
      Component = "database"
      ManagedBy = "terraform"
    },
    var.tags,
  )
}
