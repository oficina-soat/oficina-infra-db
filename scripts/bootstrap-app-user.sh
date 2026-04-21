#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TERRAFORM_DIR="${TERRAFORM_DIR:-${REPO_ROOT}/terraform/environments/lab}"
AWS_REGION="${AWS_REGION:-us-east-1}"
MASTER_SECRET_ARN="${MASTER_SECRET_ARN:-}"
DB_HOST="${DB_HOST:-}"
DB_PORT="${DB_PORT:-}"
DB_NAME="${DB_NAME:-}"
MASTER_DB_USER="${MASTER_DB_USER:-}"
MASTER_DB_PASSWORD="${MASTER_DB_PASSWORD:-}"
APP_DB_USER="${APP_DB_USER:-oficina_app}"
APP_DB_PASSWORD="${APP_DB_PASSWORD:-}"
APP_DB_ALLOW_SCHEMA_CHANGES="${APP_DB_ALLOW_SCHEMA_CHANGES:-true}"
APP_SECRET_NAME="${APP_SECRET_NAME:-}"
APP_SECRET_KMS_KEY_ID="${APP_SECRET_KMS_KEY_ID:-}"
STORE_IN_SECRETS_MANAGER="${STORE_IN_SECRETS_MANAGER:-false}"
DB_SSLMODE="${DB_SSLMODE:-require}"

usage() {
  cat <<EOF
Uso:
  $(basename "$0")

Variaveis suportadas:
  TERRAFORM_DIR               Diretorio do root module Terraform. Default: terraform/environments/lab
  AWS_REGION                  Regiao AWS. Default: us-east-1
  MASTER_SECRET_ARN           Secret do usuario master no Secrets Manager
  DB_HOST                     Endpoint do RDS. Se ausente, tenta ler do secret ou do terraform output
  DB_PORT                     Porta. Se ausente, tenta ler do secret ou do terraform output
  DB_NAME                     Nome do banco. Se ausente, tenta ler do terraform output
  MASTER_DB_USER              Usuario master. Se ausente, tenta ler do secret ou do terraform output
  MASTER_DB_PASSWORD          Senha master. Obrigatoria sem MASTER_SECRET_ARN
  APP_DB_USER                 Usuario da aplicacao. Default: oficina_app
  APP_DB_PASSWORD             Senha da aplicacao. Se ausente, o script gera uma senha
  APP_DB_ALLOW_SCHEMA_CHANGES true|false. Default: true
  STORE_IN_SECRETS_MANAGER    true|false. Default: false
  APP_SECRET_NAME             Nome/ARN da secret da aplicacao para criar/atualizar
  APP_SECRET_KMS_KEY_ID       KMS key opcional para a secret da aplicacao
  DB_SSLMODE                  SSL mode do psql. Default: require
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
  require_valid_secret_id "${MASTER_SECRET_ARN}" "MASTER_SECRET_ARN"
  require_cmd aws
  require_cmd jq
  aws secretsmanager get-secret-value \
    --region "${AWS_REGION}" \
    --secret-id "${MASTER_SECRET_ARN}" \
    --query SecretString \
    --output text
}

read_secret_field() {
  local secret_json="$1"
  local field_name="$2"
  jq -er --arg field_name "${field_name}" '.[$field_name] // empty' <<<"${secret_json}" 2>/dev/null || true
}

generate_password() {
  require_cmd openssl
  openssl rand -base64 48 | tr -d '\n' | tr '/+' '_-' | cut -c1-32
}

upsert_app_secret() {
  local secret_payload="$1"

  require_cmd aws

  if aws secretsmanager describe-secret --region "${AWS_REGION}" --secret-id "${APP_SECRET_NAME}" >/dev/null 2>&1; then
    aws secretsmanager put-secret-value \
      --region "${AWS_REGION}" \
      --secret-id "${APP_SECRET_NAME}" \
      --secret-string "${secret_payload}" >/dev/null
    return
  fi

  if [[ -n "${APP_SECRET_KMS_KEY_ID}" ]]; then
    aws secretsmanager create-secret \
      --region "${AWS_REGION}" \
      --name "${APP_SECRET_NAME}" \
      --kms-key-id "${APP_SECRET_KMS_KEY_ID}" \
      --secret-string "${secret_payload}" >/dev/null
    return
  fi

  aws secretsmanager create-secret \
    --region "${AWS_REGION}" \
    --name "${APP_SECRET_NAME}" \
    --secret-string "${secret_payload}" >/dev/null
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_cmd psql

if [[ -z "${MASTER_SECRET_ARN}" ]]; then
  MASTER_SECRET_ARN="$(read_tf_output db_master_user_secret_arn)"
fi

if [[ -n "${MASTER_SECRET_ARN}" ]]; then
  SECRET_JSON="$(read_secret_json)"

  if [[ -z "${DB_HOST}" ]]; then
    DB_HOST="$(read_secret_field "${SECRET_JSON}" host)"
  fi

  if [[ -z "${DB_PORT}" ]]; then
    DB_PORT="$(read_secret_field "${SECRET_JSON}" port)"
  fi

  if [[ -z "${MASTER_DB_USER}" ]]; then
    MASTER_DB_USER="$(read_secret_field "${SECRET_JSON}" username)"
  fi

  if [[ -z "${MASTER_DB_PASSWORD}" ]]; then
    MASTER_DB_PASSWORD="$(read_secret_field "${SECRET_JSON}" password)"
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

if [[ -z "${MASTER_DB_USER}" ]]; then
  MASTER_DB_USER="$(read_tf_output db_username)"
fi

if [[ -z "${APP_DB_PASSWORD}" ]]; then
  APP_DB_PASSWORD="$(generate_password)"
fi

require_non_empty "${DB_HOST}" "DB_HOST"
require_non_empty "${DB_PORT}" "DB_PORT"
require_non_empty "${DB_NAME}" "DB_NAME"
require_non_empty "${MASTER_DB_USER}" "MASTER_DB_USER"
require_non_empty "${MASTER_DB_PASSWORD}" "MASTER_DB_PASSWORD"
require_non_empty "${APP_DB_USER}" "APP_DB_USER"
require_non_empty "${APP_DB_PASSWORD}" "APP_DB_PASSWORD"

log "Criando ou atualizando o usuario ${APP_DB_USER} em ${DB_HOST}:${DB_PORT}/${DB_NAME}"

PGPASSWORD="${MASTER_DB_PASSWORD}" psql \
  "host=${DB_HOST} port=${DB_PORT} dbname=${DB_NAME} user=${MASTER_DB_USER} sslmode=${DB_SSLMODE}" \
  -v ON_ERROR_STOP=1 \
  --set=app_db_user="${APP_DB_USER}" \
  --set=app_db_password="${APP_DB_PASSWORD}" \
  --set=app_db_allow_schema_changes="${APP_DB_ALLOW_SCHEMA_CHANGES}" \
  <<'SQL'
DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'app_db_user') THEN
    EXECUTE format(
      'CREATE ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION',
      :'app_db_user',
      :'app_db_password'
    );
  ELSE
    EXECUTE format(
      'ALTER ROLE %I WITH LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION',
      :'app_db_user',
      :'app_db_password'
    );
  END IF;

  EXECUTE format('GRANT CONNECT ON DATABASE %I TO %I', current_database(), :'app_db_user');
  EXECUTE format('GRANT USAGE ON SCHEMA public TO %I', :'app_db_user');
  EXECUTE format(
    'GRANT SELECT, INSERT, UPDATE, DELETE, TRIGGER, REFERENCES ON ALL TABLES IN SCHEMA public TO %I',
    :'app_db_user'
  );
  EXECUTE format(
    'GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO %I',
    :'app_db_user'
  );
  EXECUTE format(
    'ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE, TRIGGER, REFERENCES ON TABLES TO %I',
    :'app_db_user'
  );
  EXECUTE format(
    'ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO %I',
    :'app_db_user'
  );

  IF :'app_db_allow_schema_changes' = 'true' THEN
    EXECUTE format('GRANT CREATE ON SCHEMA public TO %I', :'app_db_user');
  END IF;
END
$do$;
SQL

if [[ "${STORE_IN_SECRETS_MANAGER}" == "true" ]]; then
  require_non_empty "${APP_SECRET_NAME}" "APP_SECRET_NAME"
  require_cmd jq

  APP_SECRET_PAYLOAD="$(jq -nc \
    --arg engine "postgres" \
    --arg host "${DB_HOST}" \
    --arg dbname "${DB_NAME}" \
    --arg username "${APP_DB_USER}" \
    --arg password "${APP_DB_PASSWORD}" \
    --arg port "${DB_PORT}" \
    --arg sslmode "${DB_SSLMODE}" \
    '{engine: $engine, host: $host, port: $port, dbname: $dbname, username: $username, password: $password, sslmode: $sslmode}')"

  upsert_app_secret "${APP_SECRET_PAYLOAD}"
  log "Secret da aplicacao criada/atualizada em ${APP_SECRET_NAME}"
fi

cat <<EOF
APP_DB_USER=${APP_DB_USER}
APP_DB_PASSWORD=${APP_DB_PASSWORD}
DB_NAME=${DB_NAME}
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_SSLMODE=${DB_SSLMODE}
EOF
