#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
export REPO_ROOT

source "${SCRIPT_DIR}/../lib/common.sh"

AWS_REGION="${AWS_REGION:-${OFICINA_AWS_REGION}}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-}"
TF_STATE_BUCKET="${TF_STATE_BUCKET:-}"
TF_STATE_KEY="${TF_STATE_KEY:-${OFICINA_TF_STATE_KEY}}"
TF_STATE_REGION="${TF_STATE_REGION:-${AWS_REGION}}"
TF_STATE_DYNAMODB_TABLE="${TF_STATE_DYNAMODB_TABLE:-}"
BOOTSTRAP_APP_USER="${BOOTSTRAP_APP_USER:-false}"
APP_DB_USER="${APP_DB_USER:-${OFICINA_APP_DB_USER}}"
APP_DB_PASSWORD="${APP_DB_PASSWORD:-}"
APP_DB_ALLOW_SCHEMA_CHANGES="${APP_DB_ALLOW_SCHEMA_CHANGES:-true}"
STORE_IN_SECRETS_MANAGER="${STORE_IN_SECRETS_MANAGER:-false}"
APP_SECRET_NAME="${APP_SECRET_NAME:-}"
APP_SECRET_KMS_KEY_ID="${APP_SECRET_KMS_KEY_ID:-}"
DB_SSLMODE="${DB_SSLMODE:-${OFICINA_DB_SSLMODE}}"
APPLY_K8S_SECRET="${APPLY_K8S_SECRET:-false}"
K8S_NAMESPACE="${K8S_NAMESPACE:-${OFICINA_K8S_NAMESPACE}}"
K8S_SECRET_NAME="${K8S_SECRET_NAME:-${OFICINA_DB_K8S_SECRET_NAME}}"
RUN_DB_MIGRATIONS="${RUN_DB_MIGRATIONS:-true}"
RUN_DB_IMPORT="${RUN_DB_IMPORT:-true}"
IMPORT_FILE="${IMPORT_FILE:-}"
MIGRATIONS_DIR="${MIGRATIONS_DIR:-}"
FLYWAY_DOCKER_IMAGE="${FLYWAY_DOCKER_IMAGE:-${OFICINA_FLYWAY_DOCKER_IMAGE}}"
FLYWAY_BASELINE_ON_MIGRATE="${FLYWAY_BASELINE_ON_MIGRATE:-true}"
AUTO_ALLOW_CI_RUNNER_CIDR="${AUTO_ALLOW_CI_RUNNER_CIDR:-true}"
CI_RUNNER_PUBLIC_IP_URL="${CI_RUNNER_PUBLIC_IP_URL:-https://checkip.amazonaws.com}"
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

append_allowed_cidr_block() {
  local cidr_block="$1"
  local allowed_cidr_blocks="${TF_VAR_allowed_cidr_blocks:-[]}"

  require_cmd jq

  if [[ -z "${allowed_cidr_blocks}" ]]; then
    allowed_cidr_blocks="[]"
  fi

  if ! jq -e 'type == "array" and all(.[]; type == "string")' <<<"${allowed_cidr_blocks}" >/dev/null; then
    echo "TF_VAR_allowed_cidr_blocks deve ser uma lista JSON de strings para permitir merge automatico do CIDR do runner." >&2
    exit 1
  fi

  TF_VAR_allowed_cidr_blocks="$(
    jq -c --arg cidr_block "${cidr_block}" \
      'if index($cidr_block) then . else . + [$cidr_block] end' \
      <<<"${allowed_cidr_blocks}"
  )"
  export TF_VAR_allowed_cidr_blocks
}

configure_ci_runner_db_access() {
  local runner_ip=""
  local runner_cidr=""

  if [[ "${AUTO_ALLOW_CI_RUNNER_CIDR}" != "true" ]]; then
    return
  fi

  if [[ "${RUN_DB_MIGRATIONS}" != "true" && "${RUN_DB_IMPORT}" != "true" && "${BOOTSTRAP_APP_USER}" != "true" ]]; then
    return
  fi

  require_cmd curl

  runner_ip="$(curl -fsSL --max-time 10 "${CI_RUNNER_PUBLIC_IP_URL}" | tr -d '[:space:]')"

  if [[ ! "${runner_ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "Nao foi possivel descobrir um IPv4 publico valido para liberar acesso do runner ao RDS: ${runner_ip}" >&2
    exit 1
  fi

  runner_cidr="${runner_ip}/32"
  append_allowed_cidr_block "${runner_cidr}"
  log "Liberando acesso do runner atual ao RDS via ${runner_cidr}."
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
configure_ci_runner_db_access

TERRAFORM_ACTION=apply \
AWS_REGION="${AWS_REGION}" \
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME}" \
TF_STATE_BUCKET="${TF_STATE_BUCKET}" \
TF_STATE_KEY="${TF_STATE_KEY}" \
TF_STATE_REGION="${TF_STATE_REGION}" \
TF_STATE_DYNAMODB_TABLE="${TF_STATE_DYNAMODB_TABLE}" \
CI_TERRAFORM_OUTPUT_FILE="${tf_outputs_file}" \
bash "${REPO_ROOT}/scripts/actions/ci-terraform.sh"

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
  DB_SSLMODE="${DB_SSLMODE}" \
  AWS_REGION="${AWS_REGION}" \
  bash "${REPO_ROOT}/scripts/manual/bootstrap-app-user.sh" | tee "${bootstrap_output_file}" >/dev/null

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
  DB_SSLMODE="${DB_SSLMODE}" \
  MIGRATIONS_DIR="${MIGRATIONS_DIR:-}" \
  FLYWAY_DOCKER_IMAGE="${FLYWAY_DOCKER_IMAGE:-}" \
  FLYWAY_BASELINE_ON_MIGRATE="${FLYWAY_BASELINE_ON_MIGRATE}" \
  bash "${REPO_ROOT}/scripts/manual/run-db-migrations.sh" migrate
fi

if [[ "${RUN_DB_IMPORT}" == "true" ]]; then
  log "Executando seed import.sql."
  AWS_REGION="${AWS_REGION}" \
  DB_SECRET_ARN="${TF_DB_SECRET_ARN}" \
  DB_HOST="${TF_DB_HOST}" \
  DB_PORT="${TF_DB_PORT}" \
  DB_NAME="${TF_DB_NAME}" \
  DB_USER="${TF_DB_USER}" \
  DB_SSLMODE="${DB_SSLMODE}" \
  IMPORT_FILE="${IMPORT_FILE:-}" \
  bash "${REPO_ROOT}/scripts/manual/run-rds-import.sh"
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
  DB_SSLMODE="${DB_SSLMODE}" \
  bash "${REPO_ROOT}/scripts/manual/apply-k8s-secret.sh"
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
DB_SSLMODE="${DB_SSLMODE}" \
bash "${REPO_ROOT}/scripts/manual/apply-k8s-secret.sh"
