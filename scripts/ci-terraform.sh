#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TERRAFORM_DIR="${TERRAFORM_DIR:-${REPO_ROOT}/terraform/environments/lab}"
AWS_REGION="${AWS_REGION:-}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-}"
SHARED_INFRA_NAME="${SHARED_INFRA_NAME:-${EKS_CLUSTER_NAME}}"
TF_STATE_BUCKET="${TF_STATE_BUCKET:-}"
TF_STATE_KEY="${TF_STATE_KEY:-oficina/lab/database/terraform.tfstate}"
TF_STATE_REGION="${TF_STATE_REGION:-${AWS_REGION}}"
TF_STATE_DYNAMODB_TABLE="${TF_STATE_DYNAMODB_TABLE:-}"
TERRAFORM_ACTION="${TERRAFORM_ACTION:-apply}"
BACKEND_S3_TEMPLATE="${TERRAFORM_DIR}/backend.s3.tf.example"
EFFECTIVE_TF_STATE_BUCKET=""
backend_override_file=""

cleanup() {
  if [[ -n "${backend_override_file}" && -f "${backend_override_file}" ]]; then
    rm -f "${backend_override_file}"
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

normalize_optional_envs() {
  unset_if_empty "EKS_CLUSTER_NAME"
  unset_if_empty "SHARED_INFRA_NAME"
  unset_if_empty "TF_STATE_BUCKET"
  unset_if_empty "TF_STATE_DYNAMODB_TABLE"
  unset_if_empty "TF_VAR_shared_infra_name"
  unset_if_empty "TF_VAR_eks_cluster_name"
  unset_if_empty "TF_VAR_vpc_id"
  unset_if_empty "TF_VAR_subnet_ids"
  unset_if_empty "TF_VAR_azs"
  unset_if_empty "TF_VAR_public_subnet_cidrs"
  unset_if_empty "TF_VAR_allowed_security_group_ids"
  unset_if_empty "TF_VAR_allowed_cidr_blocks"
  unset_if_empty "TF_VAR_terraform_shared_data_bucket_name"
  unset_if_empty "TF_VAR_enabled_cloudwatch_logs_exports"
  unset_if_empty "TF_VAR_tags"
}

aws_caller_account_id() {
  aws sts get-caller-identity --query 'Account' --output text
}

resolve_shared_infra_name() {
  if [[ -n "${TF_VAR_shared_infra_name:-}" ]]; then
    printf '%s\n' "${TF_VAR_shared_infra_name}"
    return
  fi

  if [[ -n "${SHARED_INFRA_NAME:-}" ]]; then
    printf '%s\n' "${SHARED_INFRA_NAME}"
    return
  fi

  if [[ -n "${TF_VAR_eks_cluster_name:-}" ]]; then
    printf '%s\n' "${TF_VAR_eks_cluster_name}"
    return
  fi

  if [[ -n "${EKS_CLUSTER_NAME:-}" ]]; then
    printf '%s\n' "${EKS_CLUSTER_NAME}"
    return
  fi

  printf 'eks-lab\n'
}

resolve_shared_bucket_name() {
  if [[ -n "${TF_VAR_terraform_shared_data_bucket_name:-}" ]]; then
    printf '%s\n' "${TF_VAR_terraform_shared_data_bucket_name}"
    return
  fi

  printf 'tf-shared-%s-%s-%s\n' \
    "$(resolve_shared_infra_name)" \
    "$(aws_caller_account_id)" \
    "${TF_VAR_region}"
}

resolve_effective_backend_bucket() {
  if [[ -n "${TF_STATE_BUCKET:-}" ]]; then
    printf '%s\n' "${TF_STATE_BUCKET}"
    return
  fi

  resolve_shared_bucket_name
}

create_backend_override() {
  if [[ ! -f "${BACKEND_S3_TEMPLATE}" ]]; then
    echo "Template de backend S3 nao encontrado: ${BACKEND_S3_TEMPLATE}" >&2
    exit 1
  fi

  backend_override_file="$(mktemp "${TERRAFORM_DIR}/backend-ci-XXXXXX.tf")"
  cp "${BACKEND_S3_TEMPLATE}" "${backend_override_file}"
}

disable_remote_backend_override() {
  if [[ -n "${backend_override_file}" && -f "${backend_override_file}" ]]; then
    rm -f "${backend_override_file}"
    backend_override_file=""
  fi
}

terraform_remote_backend_args() {
  local args=(
    "-backend-config=bucket=${EFFECTIVE_TF_STATE_BUCKET}"
    "-backend-config=key=${TF_STATE_KEY}"
    "-backend-config=region=${TF_STATE_REGION}"
    "-backend-config=encrypt=true"
  )

  if [[ -n "${TF_STATE_DYNAMODB_TABLE:-}" ]]; then
    args+=("-backend-config=dynamodb_table=${TF_STATE_DYNAMODB_TABLE}")
  fi

  printf '%s\n' "${args[@]}"
}

terraform_init_remote() {
  mapfile -t backend_args < <(terraform_remote_backend_args)
  terraform -chdir="${TERRAFORM_DIR}" init -input=false -reconfigure "${backend_args[@]}"
}

terraform_migrate_state_remote() {
  mapfile -t backend_args < <(terraform_remote_backend_args)
  terraform -chdir="${TERRAFORM_DIR}" init -input=false -migrate-state -force-copy "${backend_args[@]}"
}

terraform_init_local() {
  terraform -chdir="${TERRAFORM_DIR}" init -input=false -reconfigure
}

terraform_migrate_state_local() {
  disable_remote_backend_override
  terraform -chdir="${TERRAFORM_DIR}" init -input=false -migrate-state -force-copy
}

terraform_state_manages_shared_bucket_resource() {
  terraform -chdir="${TERRAFORM_DIR}" state list 2>/dev/null | grep -q '^module\.terraform_shared_data_bucket\[0\]\.aws_s3_bucket\.this$'
}

terraform_state_manages_network_resource() {
  terraform -chdir="${TERRAFORM_DIR}" state list 2>/dev/null | grep -q '^module\.network\[0\]\.aws_vpc\.this$'
}

aws_bucket_exists() {
  aws s3api head-bucket \
    --region "${TF_STATE_REGION}" \
    --bucket "${EFFECTIVE_TF_STATE_BUCKET}" >/dev/null 2>&1
}

remote_state_exists() {
  aws s3api head-object \
    --region "${TF_STATE_REGION}" \
    --bucket "${EFFECTIVE_TF_STATE_BUCKET}" \
    --key "${TF_STATE_KEY}" >/dev/null 2>&1
}

set_shared_bucket_mode() {
  local shared_bucket_name=""
  shared_bucket_name="$(resolve_shared_bucket_name)"
  export TF_VAR_terraform_shared_data_bucket_name="${shared_bucket_name}"

  if terraform_state_manages_shared_bucket_resource; then
    log "Bucket compartilhado ${shared_bucket_name} ja esta no state deste ambiente; mantendo gerenciamento pelo Terraform."
    export TF_VAR_create_terraform_shared_data_bucket="true"
  elif aws s3api head-bucket --bucket "${shared_bucket_name}" >/dev/null 2>&1; then
    log "Bucket compartilhado ${shared_bucket_name} ja existe fora do state deste ambiente; reutilizando sem tentar recriar."
    export TF_VAR_create_terraform_shared_data_bucket="false"
  else
    log "Bucket compartilhado ${shared_bucket_name} ainda nao existe; habilitando criacao automatica."
    export TF_VAR_create_terraform_shared_data_bucket="true"
  fi
}

db_resource_exists() {
  local db_identifier="$1"

  aws rds describe-db-instances \
    --region "${AWS_REGION}" \
    --db-instance-identifier "${db_identifier}" >/dev/null 2>&1
}

db_subnet_group_exists() {
  local subnet_group_name="$1"

  aws rds describe-db-subnet-groups \
    --region "${AWS_REGION}" \
    --db-subnet-group-name "${subnet_group_name}" >/dev/null 2>&1
}

db_parameter_group_exists() {
  local parameter_group_name="$1"

  local matches=""
  matches="$(aws rds describe-db-parameter-groups \
    --region "${AWS_REGION}" \
    --query "DBParameterGroups[?DBParameterGroupName==\`${parameter_group_name}\`].DBParameterGroupName" \
    --output text 2>/dev/null || true)"

  [[ -n "${matches}" && "${matches}" != "None" ]]
}

db_security_group_exists() {
  local security_group_name="$1"

  local matches=""
  matches="$(aws ec2 describe-security-groups \
    --region "${AWS_REGION}" \
    --filters "Name=group-name,Values=${security_group_name}" \
    --query 'SecurityGroups[].GroupId' \
    --output text 2>/dev/null || true)"

  [[ -n "${matches}" && "${matches}" != "None" ]]
}

cleanup_missing_remote_state_existing_db_resources() {
  local db_identifier="${TF_VAR_db_identifier:-oficina-postgres-lab}"
  local subnet_group_name="${db_identifier}-subnet-group"
  local parameter_group_name="${db_identifier}-pg"
  local security_group_name="${db_identifier}-sg"
  local found_existing_resource="false"

  if db_resource_exists "${db_identifier}"; then
    found_existing_resource="true"
  fi

  if db_subnet_group_exists "${subnet_group_name}" || db_parameter_group_exists "${parameter_group_name}" || db_security_group_exists "${security_group_name}"; then
    found_existing_resource="true"
  fi

  if [[ "${found_existing_resource}" != "true" ]]; then
    return
  fi

  log "Recursos orfaos do banco encontrados sem state remoto em ${EFFECTIVE_TF_STATE_BUCKET}/${TF_STATE_KEY}; executando cleanup limitado ao banco antes do apply."

  CLEANUP_DB_ONLY=true \
  AWS_REGION="${AWS_REGION}" \
  EKS_CLUSTER_NAME="${TF_VAR_eks_cluster_name:-${EKS_CLUSTER_NAME:-}}" \
  SHARED_INFRA_NAME="${TF_VAR_shared_infra_name:-${SHARED_INFRA_NAME:-}}" \
  DB_IDENTIFIER="${db_identifier}" \
  DB_SUBNET_GROUP_NAME="${subnet_group_name}" \
  DB_PARAMETER_GROUP_NAME="${parameter_group_name}" \
  TF_STATE_BUCKET="${EFFECTIVE_TF_STATE_BUCKET}" \
  TF_STATE_KEY="${TF_STATE_KEY}" \
  TF_STATE_REGION="${TF_STATE_REGION}" \
  bash "${REPO_ROOT}/scripts/cleanup-orphan-db.sh"
}

read_tf_output_raw() {
  local output_name="$1"
  terraform -chdir="${TERRAFORM_DIR}" output -raw "${output_name}" 2>/dev/null || true
}

list_bucket_keys() {
  local bucket_name="$1"

  aws s3api list-object-versions \
    --region "${TF_STATE_REGION}" \
    --bucket "${bucket_name}" \
    --query 'concat(Versions[].Key, DeleteMarkers[].Key)' \
    --output text 2>/dev/null || true
}

ensure_bucket_safe_to_destroy() {
  local bucket_name="$1"
  local keys=""
  local key=""

  keys="$(list_bucket_keys "${bucket_name}")"

  if [[ -z "${keys}" || "${keys}" == "None" ]]; then
    export TF_VAR_terraform_shared_data_bucket_force_destroy="false"
    return
  fi

  for key in ${keys}; do
    if [[ "${key}" != "${TF_STATE_KEY}" ]]; then
      echo "O bucket compartilhado ${bucket_name} ainda contem objetos fora do state deste projeto (${key}). O destroy foi bloqueado para evitar apagar dados em uso por outros workloads." >&2
      exit 1
    fi
  done

  export TF_VAR_terraform_shared_data_bucket_force_destroy="true"
}

list_eks_clusters_in_vpc() {
  local vpc_id="$1"
  local cluster_names=()
  local cluster_name=""
  local cluster_vpc_id=""

  mapfile -t cluster_names < <(aws eks list-clusters --region "${AWS_REGION}" --query 'clusters[]' --output text 2>/dev/null | tr '\t' '\n')

  for cluster_name in "${cluster_names[@]}"; do
    if [[ -z "${cluster_name}" ]]; then
      continue
    fi

    cluster_vpc_id="$(aws eks describe-cluster \
      --region "${AWS_REGION}" \
      --name "${cluster_name}" \
      --query 'cluster.resourcesVpcConfig.vpcId' \
      --output text 2>/dev/null || true)"

    if [[ "${cluster_vpc_id}" == "${vpc_id}" ]]; then
      printf '%s\n' "${cluster_name}"
    fi
  done
}

ensure_safe_destroy() {
  local db_identifier="${TF_VAR_db_identifier:-oficina-postgres-lab}"
  local subnet_group_name=""
  local security_group_id=""
  local vpc_id=""
  local bucket_name=""
  local other_db_instances=""
  local other_sg_db_instances=""
  local cluster_names=""
  local foreign_enis=""

  subnet_group_name="$(read_tf_output_raw db_subnet_group_name)"
  security_group_id="$(read_tf_output_raw db_security_group_id)"
  vpc_id="$(read_tf_output_raw vpc_id)"
  bucket_name="$(read_tf_output_raw terraform_shared_data_bucket_name)"

  if [[ -n "${subnet_group_name}" ]]; then
    other_db_instances="$(aws rds describe-db-instances \
      --region "${AWS_REGION}" \
      --query "DBInstances[?DBSubnetGroup.DBSubnetGroupName==\`${subnet_group_name}\` && DBInstanceIdentifier!=\`${db_identifier}\`].DBInstanceIdentifier" \
      --output text 2>/dev/null || true)"

    if [[ -n "${other_db_instances}" && "${other_db_instances}" != "None" ]]; then
      echo "O subnet group ${subnet_group_name} ainda esta em uso por outras instancias RDS: ${other_db_instances}. O destroy foi bloqueado." >&2
      exit 1
    fi
  fi

  if [[ -n "${security_group_id}" ]]; then
    other_sg_db_instances="$(aws rds describe-db-instances \
      --region "${AWS_REGION}" \
      --query "DBInstances[?length(VpcSecurityGroups[?VpcSecurityGroupId==\`${security_group_id}\`]) > \`0\` && DBInstanceIdentifier!=\`${db_identifier}\`].DBInstanceIdentifier" \
      --output text 2>/dev/null || true)"

    if [[ -n "${other_sg_db_instances}" && "${other_sg_db_instances}" != "None" ]]; then
      echo "O security group ${security_group_id} ainda esta em uso por outras instancias RDS: ${other_sg_db_instances}. O destroy foi bloqueado." >&2
      exit 1
    fi
  fi

  if terraform_state_manages_network_resource && [[ -n "${vpc_id}" ]]; then
    cluster_names="$(list_eks_clusters_in_vpc "${vpc_id}")"

    if [[ -n "${cluster_names}" ]]; then
      echo "A VPC ${vpc_id} ainda esta sendo usada por clusters EKS (${cluster_names//$'\n'/ }). O destroy foi bloqueado." >&2
      exit 1
    fi

    other_db_instances="$(aws rds describe-db-instances \
      --region "${AWS_REGION}" \
      --query "DBInstances[?DBSubnetGroup.VpcId==\`${vpc_id}\` && DBInstanceIdentifier!=\`${db_identifier}\`].DBInstanceIdentifier" \
      --output text 2>/dev/null || true)"

    if [[ -n "${other_db_instances}" && "${other_db_instances}" != "None" ]]; then
      echo "A VPC ${vpc_id} ainda contem outras instancias RDS (${other_db_instances}). O destroy foi bloqueado." >&2
      exit 1
    fi

    if [[ -n "${security_group_id}" ]]; then
      foreign_enis="$(aws ec2 describe-network-interfaces \
        --region "${AWS_REGION}" \
        --filters "Name=vpc-id,Values=${vpc_id}" \
        --query "NetworkInterfaces[?length(Groups[?GroupId==\`${security_group_id}\`])==\`0\`].NetworkInterfaceId" \
        --output text 2>/dev/null || true)"

      if [[ -n "${foreign_enis}" && "${foreign_enis}" != "None" ]]; then
        echo "A VPC ${vpc_id} ainda possui interfaces de rede fora do banco (${foreign_enis}). O destroy foi bloqueado para evitar apagar uma rede compartilhada." >&2
        exit 1
      fi
    fi
  fi

  if terraform_state_manages_shared_bucket_resource && [[ -n "${bucket_name}" ]]; then
    ensure_bucket_safe_to_destroy "${bucket_name}"
  fi
}

run_apply() {
  EFFECTIVE_TF_STATE_BUCKET="$(resolve_effective_backend_bucket)"

  if aws_bucket_exists; then
    export TF_VAR_terraform_shared_data_bucket_name="${EFFECTIVE_TF_STATE_BUCKET}"

    if remote_state_exists; then
      log "Bucket ${EFFECTIVE_TF_STATE_BUCKET} e state remoto encontrados; configurando backend remoto."
      create_backend_override
      terraform_init_remote

      if terraform_state_manages_shared_bucket_resource; then
        log "Bucket ${EFFECTIVE_TF_STATE_BUCKET} ja esta no state deste ambiente; mantendo gerenciamento pelo Terraform."
        export TF_VAR_create_terraform_shared_data_bucket="true"
      else
        log "Bucket ${EFFECTIVE_TF_STATE_BUCKET} existe fora do state deste ambiente; reutilizando sem tentar recriar."
        export TF_VAR_create_terraform_shared_data_bucket="false"
      fi
    else
      cleanup_missing_remote_state_existing_db_resources

      log "Bucket ${EFFECTIVE_TF_STATE_BUCKET} existe, mas o state remoto ainda nao foi criado. Executando bootstrap local e migrando o state ao final."
      export TF_VAR_create_terraform_shared_data_bucket="false"
      terraform_init_local
      set_shared_bucket_mode
      terraform -chdir="${TERRAFORM_DIR}" apply -input=false -auto-approve

      log "Migrando o state local para o backend S3 em ${EFFECTIVE_TF_STATE_BUCKET}."
      create_backend_override
      terraform_migrate_state_remote
    fi
  else
    log "Bucket de backend ${EFFECTIVE_TF_STATE_BUCKET} ainda nao existe; executando bootstrap local para cria-lo."
    cleanup_missing_remote_state_existing_db_resources
    terraform_init_local
    set_shared_bucket_mode
    terraform -chdir="${TERRAFORM_DIR}" apply -input=false -auto-approve

    log "Migrando o state local para o backend S3 em ${EFFECTIVE_TF_STATE_BUCKET}."
    create_backend_override
    terraform_migrate_state_remote
  fi

  export TF_VAR_terraform_shared_data_bucket_name="${EFFECTIVE_TF_STATE_BUCKET}"
  set_shared_bucket_mode
  terraform -chdir="${TERRAFORM_DIR}" apply -input=false -auto-approve
}

run_destroy() {
  EFFECTIVE_TF_STATE_BUCKET="$(resolve_effective_backend_bucket)"

  if aws_bucket_exists; then
    export TF_VAR_terraform_shared_data_bucket_name="${EFFECTIVE_TF_STATE_BUCKET}"

    if ! remote_state_exists; then
      echo "O bucket de backend ${EFFECTIVE_TF_STATE_BUCKET} existe, mas o state remoto ${TF_STATE_KEY} nao foi encontrado. Sem esse state, o workflow nao consegue destruir a infraestrutura com seguranca." >&2
      exit 1
    fi

    log "Bucket ${EFFECTIVE_TF_STATE_BUCKET} existe; carregando state do backend remoto."
    create_backend_override
    terraform_init_remote

    if terraform_state_manages_shared_bucket_resource; then
      log "O bucket de backend faz parte do state; migrando o state para backend local antes do destroy."
      export TF_VAR_create_terraform_shared_data_bucket="true"
      terraform_migrate_state_local
    else
      log "O bucket de backend e externo ao state deste ambiente; destruindo a infraestrutura sem tocar no bucket."
      export TF_VAR_create_terraform_shared_data_bucket="false"
    fi
  else
    echo "O bucket de backend ${EFFECTIVE_TF_STATE_BUCKET} nao existe. Sem state remoto persistente, o workflow nao consegue destruir a infraestrutura criada em execucoes anteriores do GitHub Actions." >&2
    exit 1
  fi

  export TF_VAR_terraform_shared_data_bucket_name="${EFFECTIVE_TF_STATE_BUCKET}"
  set_shared_bucket_mode
  ensure_safe_destroy
  terraform -chdir="${TERRAFORM_DIR}" destroy -input=false -auto-approve
}

normalize_optional_envs

require_cmd aws
require_cmd terraform
require_non_empty "${AWS_REGION}" "AWS_REGION"

export TF_VAR_region="${TF_VAR_region:-${AWS_REGION}}"
export TF_VAR_shared_infra_name="${TF_VAR_shared_infra_name:-$(resolve_shared_infra_name)}"
export TF_VAR_eks_cluster_name="${TF_VAR_eks_cluster_name:-${EKS_CLUSTER_NAME:-${TF_VAR_shared_infra_name}}}"

case "${TERRAFORM_ACTION}" in
  apply)
    run_apply
    ;;
  destroy)
    run_destroy
    ;;
  *)
    echo "TERRAFORM_ACTION invalida: ${TERRAFORM_ACTION}. Use apply ou destroy." >&2
    exit 1
    ;;
esac
