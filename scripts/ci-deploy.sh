#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

AWS_REGION="${AWS_REGION:-}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-}"
TF_STATE_BUCKET="${TF_STATE_BUCKET:-}"
TF_STATE_KEY="${TF_STATE_KEY:-oficina/lab/database/terraform.tfstate}"
TF_STATE_REGION="${TF_STATE_REGION:-${AWS_REGION}}"
TF_STATE_DYNAMODB_TABLE="${TF_STATE_DYNAMODB_TABLE:-}"
BOOTSTRAP_APP_USER="${BOOTSTRAP_APP_USER:-false}"
APP_DB_USER="${APP_DB_USER:-oficina_app}"
APP_DB_PASSWORD="${APP_DB_PASSWORD:-}"
APP_DB_ALLOW_SCHEMA_CHANGES="${APP_DB_ALLOW_SCHEMA_CHANGES:-true}"
STORE_IN_SECRETS_MANAGER="${STORE_IN_SECRETS_MANAGER:-false}"
APP_SECRET_NAME="${APP_SECRET_NAME:-}"
APP_SECRET_KMS_KEY_ID="${APP_SECRET_KMS_KEY_ID:-}"
APPLY_K8S_SECRET="${APPLY_K8S_SECRET:-false}"
K8S_NAMESPACE="${K8S_NAMESPACE:-default}"
K8S_SECRET_NAME="${K8S_SECRET_NAME:-oficina-database-env}"
RUN_DB_MIGRATIONS="${RUN_DB_MIGRATIONS:-true}"
MIGRATIONS_DIR="${MIGRATIONS_DIR:-}"
FLYWAY_DOCKER_IMAGE="${FLYWAY_DOCKER_IMAGE:-}"
FLYWAY_BASELINE_ON_MIGRATE="${FLYWAY_BASELINE_ON_MIGRATE:-true}"
bootstrap_output_file=""
tf_outputs_file=""
TF_DB_HOST=""
TF_DB_PORT=""
TF_DB_NAME=""
TF_DB_USER=""
TF_DB_SECRET_ARN=""

cleanup() {
  if [[ -n "${bootstrap_output_file}" && -f "${bootstrap_output_file}" ]]; then
    rm -f "${bootstrap_output_file}"
  fi

  if [[ -n "${tf_outputs_file}" && -f "${tf_outputs_file}" ]]; then
    rm -f "${tf_outputs_file}"
  fi
}

trap cleanup EXIT

log() {
  printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Comando obrigatorio nao encontrado: $1" >&2
    exit 1
  fi
}

read_output_value() {
  local file="$1"
  local key="$2"
  awk -F= -v target="${key}" '$1 == target { print substr($0, index($0, "=") + 1) }' "${file}"
}

require_non_empty() {
  local value="$1"
  local name="$2"

  if [[ -z "${value}" ]]; then
    echo "Variavel obrigatoria ausente: ${name}" >&2
    exit 1
  fi
}

load_tf_outputs() {
  TF_DB_HOST="$(read_output_value "${tf_outputs_file}" DB_HOST)"
  TF_DB_PORT="$(read_output_value "${tf_outputs_file}" DB_PORT)"
  TF_DB_NAME="$(read_output_value "${tf_outputs_file}" DB_NAME)"
  TF_DB_USER="$(read_output_value "${tf_outputs_file}" DB_USER)"
  TF_DB_SECRET_ARN="$(read_output_value "${tf_outputs_file}" DB_SECRET_ARN)"

  require_non_empty "${TF_DB_HOST}" "DB_HOST"
  require_non_empty "${TF_DB_PORT}" "DB_PORT"
  require_non_empty "${TF_DB_NAME}" "DB_NAME"
  require_non_empty "${TF_DB_USER}" "DB_USER"
  require_non_empty "${TF_DB_SECRET_ARN}" "DB_SECRET_ARN"
}

read_bootstrap_output_value() {
  local key="$1"
  read_output_value "${bootstrap_output_file}" "${key}"
}

require_cmd aws
require_cmd terraform

if [[ "${BOOTSTRAP_APP_USER}" == "true" ]]; then
  require_cmd psql
fi

if [[ "${APPLY_K8S_SECRET}" == "true" ]]; then
  require_cmd kubectl
fi

tf_outputs_file="$(mktemp)"

TERRAFORM_ACTION=apply \
AWS_REGION="${AWS_REGION}" \
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME}" \
TF_STATE_BUCKET="${TF_STATE_BUCKET}" \
TF_STATE_KEY="${TF_STATE_KEY}" \
TF_STATE_REGION="${TF_STATE_REGION}" \
TF_STATE_DYNAMODB_TABLE="${TF_STATE_DYNAMODB_TABLE}" \
CI_TERRAFORM_OUTPUT_FILE="${tf_outputs_file}" \
bash "${REPO_ROOT}/scripts/ci-terraform.sh"

load_tf_outputs

if [[ "${BOOTSTRAP_APP_USER}" == "true" ]]; then
  bootstrap_output_file="$(mktemp)"

  MASTER_SECRET_ARN="${TF_DB_SECRET_ARN}" \
  DB_HOST="${TF_DB_HOST}" \
  DB_PORT="${TF_DB_PORT}" \
  DB_NAME="${TF_DB_NAME}" \
  MASTER_DB_USER="${TF_DB_USER}" \
  APP_DB_USER="${APP_DB_USER}" \
  APP_DB_PASSWORD="${APP_DB_PASSWORD}" \
  APP_DB_ALLOW_SCHEMA_CHANGES="${APP_DB_ALLOW_SCHEMA_CHANGES}" \
  STORE_IN_SECRETS_MANAGER="${STORE_IN_SECRETS_MANAGER}" \
  APP_SECRET_NAME="${APP_SECRET_NAME}" \
  APP_SECRET_KMS_KEY_ID="${APP_SECRET_KMS_KEY_ID}" \
  AWS_REGION="${AWS_REGION}" \
  bash "${REPO_ROOT}/scripts/bootstrap-app-user.sh" | tee "${bootstrap_output_file}" >/dev/null

  log "Usuario de aplicacao bootstrapado."
fi

if [[ "${RUN_DB_MIGRATIONS}" == "true" ]]; then
  log "Executando migrations Flyway."
  AWS_REGION="${AWS_REGION}" \
  DB_SECRET_ARN="${TF_DB_SECRET_ARN}" \
  DB_HOST="${TF_DB_HOST}" \
  DB_PORT="${TF_DB_PORT}" \
  DB_NAME="${TF_DB_NAME}" \
  DB_USER="${TF_DB_USER}" \
  MIGRATIONS_DIR="${MIGRATIONS_DIR:-}" \
  FLYWAY_DOCKER_IMAGE="${FLYWAY_DOCKER_IMAGE:-}" \
  FLYWAY_BASELINE_ON_MIGRATE="${FLYWAY_BASELINE_ON_MIGRATE}" \
  bash "${REPO_ROOT}/scripts/run-db-migrations.sh" migrate
fi

if [[ "${BOOTSTRAP_APP_USER}" != "true" ]]; then
  exit 0
fi

if [[ "${APPLY_K8S_SECRET}" != "true" ]]; then
  exit 0
fi

DB_USER="$(read_bootstrap_output_value APP_DB_USER)"
DB_PASSWORD="$(read_bootstrap_output_value APP_DB_PASSWORD)"
DB_NAME="$(read_bootstrap_output_value DB_NAME)"
DB_HOST="$(read_bootstrap_output_value DB_HOST)"
DB_PORT="$(read_bootstrap_output_value DB_PORT)"

if [[ -n "${APP_SECRET_NAME}" && "${STORE_IN_SECRETS_MANAGER}" == "true" ]]; then
  DB_SECRET_ARN="${APP_SECRET_NAME}" \
  UPDATE_KUBECONFIG=true \
  EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME}" \
  AWS_REGION="${AWS_REGION}" \
  K8S_NAMESPACE="${K8S_NAMESPACE}" \
  K8S_SECRET_NAME="${K8S_SECRET_NAME}" \
  bash "${REPO_ROOT}/scripts/apply-k8s-secret.sh"
  exit 0
fi

UPDATE_KUBECONFIG=true \
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME}" \
AWS_REGION="${AWS_REGION}" \
K8S_NAMESPACE="${K8S_NAMESPACE}" \
K8S_SECRET_NAME="${K8S_SECRET_NAME}" \
DB_USER="${DB_USER}" \
DB_PASSWORD="${DB_PASSWORD}" \
DB_NAME="${DB_NAME}" \
DB_HOST="${DB_HOST}" \
DB_PORT="${DB_PORT}" \
bash "${REPO_ROOT}/scripts/apply-k8s-secret.sh"
