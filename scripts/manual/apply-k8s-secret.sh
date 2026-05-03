#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
export REPO_ROOT

source "${SCRIPT_DIR}/../lib/common.sh"

TERRAFORM_DIR="${TERRAFORM_DIR:-${OFICINA_TERRAFORM_ENV_DIR}}"
AWS_REGION="${AWS_REGION:-${OFICINA_AWS_REGION}}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-}"
UPDATE_KUBECONFIG="${UPDATE_KUBECONFIG:-false}"
OUTPUT_ONLY="${OUTPUT_ONLY:-false}"
K8S_NAMESPACE="${K8S_NAMESPACE:-${OFICINA_K8S_NAMESPACE}}"
K8S_SECRET_NAME="${K8S_SECRET_NAME:-${OFICINA_DB_K8S_SECRET_NAME}}"
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
