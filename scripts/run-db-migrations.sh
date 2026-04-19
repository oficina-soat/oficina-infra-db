#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TERRAFORM_DIR="${TERRAFORM_DIR:-${REPO_ROOT}/terraform/environments/lab}"
MIGRATIONS_DIR="${MIGRATIONS_DIR:-${REPO_ROOT}/sql/migrations}"
AWS_REGION="${AWS_REGION:-us-east-1}"
DB_SECRET_ARN="${DB_SECRET_ARN:-}"
DB_HOST="${DB_HOST:-}"
DB_PORT="${DB_PORT:-}"
DB_NAME="${DB_NAME:-}"
DB_USER="${DB_USER:-}"
DB_PASSWORD="${DB_PASSWORD:-}"
DB_SSLMODE="${DB_SSLMODE:-require}"
FLYWAY_DOCKER_IMAGE="${FLYWAY_DOCKER_IMAGE:-redgate/flyway:12.4-alpine}"
FLYWAY_DOCKER_NETWORK="${FLYWAY_DOCKER_NETWORK:-}"
FLYWAY_SCHEMAS="${FLYWAY_SCHEMAS:-public}"
FLYWAY_TABLE="${FLYWAY_TABLE:-flyway_schema_history}"
FLYWAY_CONNECT_RETRIES="${FLYWAY_CONNECT_RETRIES:-10}"
FLYWAY_BASELINE_ON_MIGRATE="${FLYWAY_BASELINE_ON_MIGRATE:-true}"
FLYWAY_BASELINE_VERSION="${FLYWAY_BASELINE_VERSION:-1}"
FLYWAY_BASELINE_DESCRIPTION="${FLYWAY_BASELINE_DESCRIPTION:-Existing schema baseline}"
FLYWAY_CLEAN_DISABLED="${FLYWAY_CLEAN_DISABLED:-true}"

usage() {
  cat <<EOF
Uso:
  $(basename "$0") [migrate|info|validate|repair]

Variaveis suportadas:
  TERRAFORM_DIR                 Diretorio do root module Terraform. Default: terraform/environments/lab
  MIGRATIONS_DIR                Diretorio das migrations Flyway. Default: sql/migrations
  AWS_REGION                    Regiao AWS para o Secrets Manager. Default: us-east-1
  DB_SECRET_ARN                 Secret de credenciais no AWS Secrets Manager. Se ausente, tenta usar o secret master do Terraform
  DB_HOST                       Endpoint do RDS. Se ausente, tenta ler do secret ou do terraform output
  DB_PORT                       Porta. Se ausente, tenta ler do secret ou do terraform output
  DB_NAME                       Nome do banco. Se ausente, tenta ler do secret ou do terraform output
  DB_USER                       Usuario. Se ausente, tenta ler do secret ou do terraform output
  DB_PASSWORD                   Senha. Obrigatoria sem DB_SECRET_ARN
  DB_SSLMODE                    SSL mode JDBC. Default: require
  FLYWAY_DOCKER_IMAGE           Imagem Docker usada quando flyway nao esta instalado. Default: redgate/flyway:12.4-alpine
  FLYWAY_DOCKER_NETWORK         Network opcional para docker run. Ex.: host para validar contra banco local
  FLYWAY_SCHEMAS                Schemas gerenciados. Default: public
  FLYWAY_TABLE                  Tabela de historico do Flyway. Default: flyway_schema_history
  FLYWAY_BASELINE_ON_MIGRATE    Baseline automatico para schemas existentes sem historico. Default: true
  FLYWAY_BASELINE_VERSION       Versao usada no baseline automatico. Default: 1
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Comando obrigatorio nao encontrado: $1" >&2
    exit 1
  fi
}

require_non_empty() {
  local value="$1"
  local name="$2"
  if [[ -z "${value}" ]]; then
    echo "Variavel obrigatoria ausente: ${name}" >&2
    exit 1
  fi
}

require_valid_secret_id() {
  local value="$1"
  local name="$2"

  require_non_empty "${value}" "${name}"

  if [[ "${value}" == *[[:space:]]* || "${value}" == *\"* || "${value}" == *"'"* ]]; then
    echo "${name} invalido: contem espaco, quebra de linha ou aspas. Se o valor veio de terraform output no GitHub Actions, desative o terraform_wrapper do hashicorp/setup-terraform." >&2
    exit 1
  fi

  if [[ ! "${value}" =~ ^arn:[A-Za-z0-9_+=,.@:/!-]+$ && ! "${value}" =~ ^[A-Za-z0-9/_+=.@!-]+$ ]]; then
    echo "${name} invalido: informe um ARN ou nome de secret do AWS Secrets Manager." >&2
    exit 1
  fi
}

log() {
  printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

read_tf_output() {
  local output_name="$1"
  if command -v terraform >/dev/null 2>&1 && [[ -d "${TERRAFORM_DIR}" ]]; then
    terraform -chdir="${TERRAFORM_DIR}" output -raw "${output_name}" 2>/dev/null || true
  fi
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

read_secret_field() {
  local secret_json="$1"
  local field_name="$2"
  jq -er --arg field_name "${field_name}" '.[$field_name] // empty' <<<"${secret_json}" 2>/dev/null || true
}

run_flyway() {
  local command="$1"
  local jdbc_url="jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=${DB_SSLMODE}"

  if command -v flyway >/dev/null 2>&1; then
    FLYWAY_URL="${jdbc_url}" \
    FLYWAY_USER="${DB_USER}" \
    FLYWAY_PASSWORD="${DB_PASSWORD}" \
    FLYWAY_LOCATIONS="${FLYWAY_LOCATIONS:-filesystem:${MIGRATIONS_DIR}}" \
    FLYWAY_SCHEMAS="${FLYWAY_SCHEMAS}" \
    FLYWAY_TABLE="${FLYWAY_TABLE}" \
    FLYWAY_CONNECT_RETRIES="${FLYWAY_CONNECT_RETRIES}" \
    FLYWAY_BASELINE_ON_MIGRATE="${FLYWAY_BASELINE_ON_MIGRATE}" \
    FLYWAY_BASELINE_VERSION="${FLYWAY_BASELINE_VERSION}" \
    FLYWAY_BASELINE_DESCRIPTION="${FLYWAY_BASELINE_DESCRIPTION}" \
    FLYWAY_CLEAN_DISABLED="${FLYWAY_CLEAN_DISABLED}" \
    flyway "${command}"
    return
  fi

  require_cmd docker

  local docker_args=(
    run
    --rm
    -v "${MIGRATIONS_DIR}:/flyway/sql:ro"
    -e FLYWAY_URL="${jdbc_url}"
    -e FLYWAY_USER="${DB_USER}"
    -e FLYWAY_PASSWORD="${DB_PASSWORD}"
    -e FLYWAY_LOCATIONS="${FLYWAY_LOCATIONS:-filesystem:/flyway/sql}"
    -e FLYWAY_SCHEMAS="${FLYWAY_SCHEMAS}"
    -e FLYWAY_TABLE="${FLYWAY_TABLE}"
    -e FLYWAY_CONNECT_RETRIES="${FLYWAY_CONNECT_RETRIES}"
    -e FLYWAY_BASELINE_ON_MIGRATE="${FLYWAY_BASELINE_ON_MIGRATE}"
    -e FLYWAY_BASELINE_VERSION="${FLYWAY_BASELINE_VERSION}"
    -e FLYWAY_BASELINE_DESCRIPTION="${FLYWAY_BASELINE_DESCRIPTION}"
    -e FLYWAY_CLEAN_DISABLED="${FLYWAY_CLEAN_DISABLED}"
  )

  if [[ -n "${FLYWAY_DOCKER_NETWORK}" ]]; then
    docker_args+=(--network "${FLYWAY_DOCKER_NETWORK}")
  fi

  docker_args+=("${FLYWAY_DOCKER_IMAGE}" "${command}")

  docker "${docker_args[@]}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

COMMAND="${1:-migrate}"
case "${COMMAND}" in
  migrate | info | validate | repair) ;;
  *)
    echo "Comando Flyway nao suportado por este wrapper: ${COMMAND}" >&2
    usage >&2
    exit 1
    ;;
esac

if [[ ! "${MIGRATIONS_DIR}" = /* ]]; then
  MIGRATIONS_DIR="${REPO_ROOT}/${MIGRATIONS_DIR}"
fi

if [[ ! -d "${MIGRATIONS_DIR}" ]]; then
  echo "Diretorio de migrations nao encontrado: ${MIGRATIONS_DIR}" >&2
  exit 1
fi

if [[ -z "${DB_SECRET_ARN}" \
  && ( -z "${DB_HOST}" || -z "${DB_PORT}" || -z "${DB_NAME}" || -z "${DB_USER}" || -z "${DB_PASSWORD}" ) ]]; then
  DB_SECRET_ARN="$(read_tf_output db_master_user_secret_arn)"
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

log "Executando Flyway ${COMMAND} em ${DB_HOST}:${DB_PORT}/${DB_NAME}"
log "Migrations: ${MIGRATIONS_DIR}"

run_flyway "${COMMAND}"

log "Flyway ${COMMAND} concluido"
