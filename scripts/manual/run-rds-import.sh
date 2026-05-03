#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
export REPO_ROOT

source "${SCRIPT_DIR}/../lib/common.sh"

TERRAFORM_DIR="${TERRAFORM_DIR:-${OFICINA_TERRAFORM_ENV_DIR}}"
IMPORT_FILE="${IMPORT_FILE:-${OFICINA_DB_IMPORT_FILE}}"
AWS_REGION="${AWS_REGION:-${OFICINA_AWS_REGION}}"
DB_SECRET_ARN="${DB_SECRET_ARN:-}"
DB_HOST="${DB_HOST:-}"
DB_PORT="${DB_PORT:-}"
DB_NAME="${DB_NAME:-}"
DB_USER="${DB_USER:-}"
DB_PASSWORD="${DB_PASSWORD:-}"
DB_SSLMODE="${DB_SSLMODE:-${OFICINA_DB_SSLMODE}}"
PSQL_DOCKER_IMAGE="${PSQL_DOCKER_IMAGE:-${OFICINA_PSQL_DOCKER_IMAGE}}"

usage() {
  cat <<EOF
Uso:
  $(basename "$0")

Variaveis suportadas:
  TERRAFORM_DIR  Diretorio do root module Terraform. Default: terraform/environments/lab
  IMPORT_FILE    Caminho do SQL. Default: sql/import.sql
  AWS_REGION     Regiao AWS para o Secrets Manager. Default: us-east-1
  DB_SECRET_ARN  Secret de credenciais no AWS Secrets Manager
  DB_HOST        Endpoint do RDS. Se ausente, tenta ler do terraform output
  DB_PORT        Porta. Se ausente, tenta ler do terraform output
  DB_NAME        Nome do banco. Se ausente, tenta ler do terraform output
  DB_USER        Usuario. Se ausente, tenta ler do terraform output
  DB_PASSWORD    Senha do banco. Obrigatoria sem DB_SECRET_ARN
  DB_SSLMODE     SSL mode do psql. Default: require
  PSQL_DOCKER_IMAGE Imagem Docker usada quando psql nao esta instalado. Default: postgres:16-alpine
EOF
}

read_secret_json() {
  require_valid_secret_id "${DB_SECRET_ARN}" "DB_SECRET_ARN"
  require_cmd aws
  require_cmd jq
  aws secretsmanager get-secret-value \
    --region "${AWS_REGION}" \
    --secret-id "${DB_SECRET_ARN}" \
    --query SecretString \
    --output text
}

run_psql_import() {
  local connection_string="host=${DB_HOST} port=${DB_PORT} dbname=${DB_NAME} user=${DB_USER} sslmode=${DB_SSLMODE}"

  if command -v psql >/dev/null 2>&1; then
    PGPASSWORD="${DB_PASSWORD}" psql \
      "${connection_string}" \
      -v ON_ERROR_STOP=1 \
      -f "${IMPORT_FILE}"
    return
  fi

  require_cmd docker

  docker run --rm \
    -v "${IMPORT_FILE}:/import.sql:ro" \
    -e PGPASSWORD="${DB_PASSWORD}" \
    "${PSQL_DOCKER_IMAGE}" \
    psql "${connection_string}" -v ON_ERROR_STOP=1 -f /import.sql
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! "${IMPORT_FILE}" = /* ]]; then
  IMPORT_FILE="${REPO_ROOT}/${IMPORT_FILE}"
fi

if [[ ! -f "${IMPORT_FILE}" ]]; then
  echo "Arquivo SQL nao encontrado: ${IMPORT_FILE}" >&2
  exit 1
fi

if [[ -n "${DB_SECRET_ARN}" ]]; then
  SECRET_JSON="$(read_secret_json)"

  if [[ -z "${DB_HOST}" ]]; then
    DB_HOST="$(read_secret_field "${SECRET_JSON}" host)"
  fi

  if [[ -z "${DB_PORT}" ]]; then
    DB_PORT="$(read_secret_field "${SECRET_JSON}" port)"
  fi

  if [[ -z "${DB_NAME}" ]]; then
    DB_NAME="$(read_secret_field "${SECRET_JSON}" dbname)"
  fi

  if [[ -z "${DB_USER}" ]]; then
    DB_USER="$(read_secret_field "${SECRET_JSON}" username)"
  fi

  if [[ -z "${DB_PASSWORD}" ]]; then
    DB_PASSWORD="$(read_secret_field "${SECRET_JSON}" password)"
  fi
fi

if [[ -z "${DB_HOST}" ]]; then
  DB_HOST="$(read_tf_output db_endpoint)"
fi

if [[ -z "${DB_PORT}" ]]; then
  DB_PORT="$(read_tf_output db_port)"
fi

if [[ -z "${DB_NAME}" ]]; then
  DB_NAME="$(read_tf_output db_name)"
fi

if [[ -z "${DB_USER}" ]]; then
  DB_USER="$(read_tf_output db_username)"
fi

require_non_empty "${DB_HOST}" "DB_HOST"
require_non_empty "${DB_PORT}" "DB_PORT"
require_non_empty "${DB_NAME}" "DB_NAME"
require_non_empty "${DB_USER}" "DB_USER"
require_non_empty "${DB_PASSWORD}" "DB_PASSWORD"

log "Executando ${IMPORT_FILE} em ${DB_HOST}:${DB_PORT}/${DB_NAME}"
log "O import.sql e seed de laboratorio; dados existentes podem ser atualizados"

run_psql_import

log "Importacao concluida"
