#!/usr/bin/env bash

if [[ -n "${OFICINA_DB_SCRIPT_COMMON_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi

OFICINA_DB_SCRIPT_COMMON_SH_LOADED=true

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/defaults.sh"

log() {
  printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
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

unset_if_empty() {
  local name="$1"

  if [[ -v "${name}" && -z "${!name}" ]]; then
    unset "${name}"
  fi
}

is_truthy() {
  case "${1:-}" in
    true | TRUE | True | 1 | yes | YES | Yes)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
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

read_tf_output() {
  local output_name="$1"

  if command -v terraform >/dev/null 2>&1 && [[ -d "${TERRAFORM_DIR}" ]]; then
    terraform -chdir="${TERRAFORM_DIR}" output -raw "${output_name}" 2>/dev/null || true
  fi
}

read_secret_field() {
  local secret_json="$1"
  local field_name="$2"

  jq -er --arg field_name "${field_name}" '.[$field_name] // empty' <<<"${secret_json}" 2>/dev/null || true
}

read_output_value() {
  local file="$1"
  local key="$2"

  awk -F= -v target="${key}" '$1 == target { print substr($0, index($0, "=") + 1) }' "${file}"
}
