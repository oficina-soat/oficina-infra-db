#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TERRAFORM_DIR="${TERRAFORM_DIR:-${REPO_ROOT}/terraform/environments/lab}"
AWS_REGION="${AWS_REGION:-us-east-1}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-}"
UPDATE_KUBECONFIG="${UPDATE_KUBECONFIG:-false}"
OUTPUT_ONLY="${OUTPUT_ONLY:-false}"
K8S_NAMESPACE="${K8S_NAMESPACE:-default}"
K8S_SECRET_NAME="${K8S_SECRET_NAME:-oficina-database-env}"
DB_SECRET_ARN="${DB_SECRET_ARN:-}"
DB_HOST="${DB_HOST:-}"
DB_PORT="${DB_PORT:-}"
DB_NAME="${DB_NAME:-}"
DB_USER="${DB_USER:-}"
DB_PASSWORD="${DB_PASSWORD:-}"
DB_SSLMODE="${DB_SSLMODE:-}"

usage() {
  cat <<EOF
Uso:
  $(basename "$0")

Variaveis suportadas:
  TERRAFORM_DIR      Diretorio do root module Terraform. Default: terraform/environments/lab
  UPDATE_KUBECONFIG  true|false. Default: false
  EKS_CLUSTER_NAME   Obrigatoria se UPDATE_KUBECONFIG=true
  AWS_REGION         Regiao AWS. Default: us-east-1
  OUTPUT_ONLY        true|false. Default: false
  K8S_NAMESPACE      Namespace do secret. Default: default
  K8S_SECRET_NAME    Nome do secret. Default: oficina-database-env
  DB_SECRET_ARN      Secret da aplicacao no AWS Secrets Manager
  DB_HOST            Endpoint do RDS. Se ausente, tenta ler do terraform output
  DB_PORT            Porta. Se ausente, tenta ler do terraform output
  DB_NAME            Nome do banco. Se ausente, tenta ler do terraform output
  DB_USER            Usuario da aplicacao. Obrigatorio sem DB_SECRET_ARN
  DB_PASSWORD        Senha da aplicacao. Obrigatoria sem DB_SECRET_ARN
  DB_SSLMODE         SSL mode do PostgreSQL. Default: require
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

render_secret() {
  cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${K8S_SECRET_NAME}
  namespace: ${K8S_NAMESPACE}
  labels:
    app.kubernetes.io/name: postgres
    app.kubernetes.io/component: database
    app.kubernetes.io/part-of: oficina
type: Opaque
stringData:
  POSTGRES_DB: ${DB_NAME}
  POSTGRES_USER: ${DB_USER}
  POSTGRES_PASSWORD: ${DB_PASSWORD}
  POSTGRES_SSLMODE: ${DB_SSLMODE}
  DB_SSLMODE: ${DB_SSLMODE}
  QUARKUS_DATASOURCE_DB_KIND: postgresql
  QUARKUS_DATASOURCE_USERNAME: ${DB_USER}
  QUARKUS_DATASOURCE_PASSWORD: ${DB_PASSWORD}
  QUARKUS_DATASOURCE_REACTIVE_URL: postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=${DB_SSLMODE}
  QUARKUS_DATASOURCE_REACTIVE_POSTGRESQL_SSL_MODE: ${DB_SSLMODE}
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${OUTPUT_ONLY}" != "true" ]]; then
  require_cmd kubectl
fi

if [[ "${UPDATE_KUBECONFIG}" == "true" ]]; then
  require_cmd aws
  require_non_empty "${EKS_CLUSTER_NAME}" "EKS_CLUSTER_NAME"
  log "Atualizando kubeconfig do cluster ${EKS_CLUSTER_NAME}"
  aws eks update-kubeconfig --region "${AWS_REGION}" --name "${EKS_CLUSTER_NAME}"
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

  if [[ -z "${DB_SSLMODE}" ]]; then
    DB_SSLMODE="$(read_secret_field "${SECRET_JSON}" sslmode)"
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

require_non_empty "${DB_HOST}" "DB_HOST"
require_non_empty "${DB_PORT}" "DB_PORT"
require_non_empty "${DB_NAME}" "DB_NAME"
require_non_empty "${DB_USER}" "DB_USER"
require_non_empty "${DB_PASSWORD}" "DB_PASSWORD"

if [[ -z "${DB_SSLMODE}" ]]; then
  DB_SSLMODE="require"
fi

require_non_empty "${DB_SSLMODE}" "DB_SSLMODE"

if [[ "${OUTPUT_ONLY}" == "true" ]]; then
  render_secret
  exit 0
fi

log "Aplicando secret ${K8S_NAMESPACE}/${K8S_SECRET_NAME}"
render_secret | kubectl apply -f -

log "Secret aplicado"
