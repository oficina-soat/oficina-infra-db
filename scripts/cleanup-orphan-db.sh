#!/usr/bin/env bash

set -euo pipefail

AWS_REGION="${AWS_REGION:-}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-eks-lab}"
SHARED_INFRA_NAME="${SHARED_INFRA_NAME:-${EKS_CLUSTER_NAME}}"
DB_IDENTIFIER="${DB_IDENTIFIER:-oficina-postgres-lab}"
DB_SUBNET_GROUP_NAME="${DB_SUBNET_GROUP_NAME:-${DB_IDENTIFIER}-subnet-group}"
DB_PARAMETER_GROUP_NAME="${DB_PARAMETER_GROUP_NAME:-${DB_IDENTIFIER}-pg}"
TF_STATE_BUCKET="${TF_STATE_BUCKET:-}"
TF_STATE_KEY="${TF_STATE_KEY:-oficina/lab/database/terraform.tfstate}"
TF_STATE_REGION="${TF_STATE_REGION:-${AWS_REGION}}"
FINAL_SNAPSHOT_IDENTIFIER="${FINAL_SNAPSHOT_IDENTIFIER:-${DB_IDENTIFIER}-orphan-$(date '+%Y%m%d%H%M%S')}"
SKIP_FINAL_SNAPSHOT="${SKIP_FINAL_SNAPSHOT:-false}"

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

aws_caller_account_id() {
  aws sts get-caller-identity --query 'Account' --output text
}

resolve_backend_bucket() {
  if [[ -n "${TF_STATE_BUCKET:-}" ]]; then
    printf '%s\n' "${TF_STATE_BUCKET}"
    return
  fi

  printf 'tf-shared-%s-%s-%s\n' "${SHARED_INFRA_NAME}" "$(aws_caller_account_id)" "${TF_STATE_REGION}"
}

bucket_exists() {
  local bucket_name="$1"
  aws s3api head-bucket --region "${TF_STATE_REGION}" --bucket "${bucket_name}" >/dev/null 2>&1
}

remote_state_exists() {
  local bucket_name="$1"
  aws s3api head-object \
    --region "${TF_STATE_REGION}" \
    --bucket "${bucket_name}" \
    --key "${TF_STATE_KEY}" >/dev/null 2>&1
}

db_exists() {
  aws rds describe-db-instances \
    --region "${AWS_REGION}" \
    --db-instance-identifier "${DB_IDENTIFIER}" >/dev/null 2>&1
}

db_vpc_id() {
  aws rds describe-db-instances \
    --region "${AWS_REGION}" \
    --db-instance-identifier "${DB_IDENTIFIER}" \
    --query 'DBInstances[0].DBSubnetGroup.VpcId' \
    --output text 2>/dev/null || true
}

db_security_group_id() {
  aws rds describe-db-instances \
    --region "${AWS_REGION}" \
    --db-instance-identifier "${DB_IDENTIFIER}" \
    --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
    --output text 2>/dev/null || true
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

ensure_vpc_is_not_shared() {
  local vpc_id="$1"
  local sg_id="$2"
  local cluster_names=""
  local other_db_instances=""
  local foreign_enis=""

  cluster_names="$(list_eks_clusters_in_vpc "${vpc_id}")"
  if [[ -n "${cluster_names}" ]]; then
    echo "A VPC ${vpc_id} ainda esta sendo usada por clusters EKS (${cluster_names//$'\n'/ }). O cleanup foi bloqueado." >&2
    exit 1
  fi

  other_db_instances="$(aws rds describe-db-instances \
    --region "${AWS_REGION}" \
    --query "DBInstances[?DBSubnetGroup.VpcId==\`${vpc_id}\` && DBInstanceIdentifier!=\`${DB_IDENTIFIER}\`].DBInstanceIdentifier" \
    --output text 2>/dev/null || true)"

  if [[ -n "${other_db_instances}" && "${other_db_instances}" != "None" ]]; then
    echo "A VPC ${vpc_id} ainda esta em uso por outras instancias RDS (${other_db_instances}). O cleanup foi bloqueado." >&2
    exit 1
  fi

  if [[ -n "${sg_id}" && "${sg_id}" != "None" ]]; then
    foreign_enis="$(aws ec2 describe-network-interfaces \
      --region "${AWS_REGION}" \
      --filters "Name=vpc-id,Values=${vpc_id}" \
      --query "NetworkInterfaces[?length(Groups[?GroupId==\`${sg_id}\`])==\`0\`].NetworkInterfaceId" \
      --output text 2>/dev/null || true)"
  else
    foreign_enis="$(aws ec2 describe-network-interfaces \
      --region "${AWS_REGION}" \
      --filters "Name=vpc-id,Values=${vpc_id}" \
      --query 'NetworkInterfaces[].NetworkInterfaceId' \
      --output text 2>/dev/null || true)"
  fi

  if [[ -n "${foreign_enis}" && "${foreign_enis}" != "None" ]]; then
    echo "A VPC ${vpc_id} ainda possui interfaces de rede fora do banco (${foreign_enis}). O cleanup foi bloqueado." >&2
    exit 1
  fi
}

disable_db_deletion_protection() {
  aws rds modify-db-instance \
    --region "${AWS_REGION}" \
    --db-instance-identifier "${DB_IDENTIFIER}" \
    --deletion-protection false \
    --apply-immediately >/dev/null
}

delete_db_instance() {
  if [[ "${SKIP_FINAL_SNAPSHOT}" == "true" ]]; then
    aws rds delete-db-instance \
      --region "${AWS_REGION}" \
      --db-instance-identifier "${DB_IDENTIFIER}" \
      --skip-final-snapshot >/dev/null
    return
  fi

  aws rds delete-db-instance \
    --region "${AWS_REGION}" \
    --db-instance-identifier "${DB_IDENTIFIER}" \
    --final-db-snapshot-identifier "${FINAL_SNAPSHOT_IDENTIFIER}" >/dev/null
}

delete_parameter_group_if_unused() {
  local in_use=""
  in_use="$(aws rds describe-db-instances \
    --region "${AWS_REGION}" \
    --query "DBInstances[?DBParameterGroups[?DBParameterGroupName==\`${DB_PARAMETER_GROUP_NAME}\`]].DBInstanceIdentifier" \
    --output text 2>/dev/null || true)"

  if [[ -n "${in_use}" && "${in_use}" != "None" ]]; then
    echo "O parameter group ${DB_PARAMETER_GROUP_NAME} ainda esta em uso por ${in_use}. O cleanup foi bloqueado." >&2
    exit 1
  fi

  aws rds delete-db-parameter-group \
    --region "${AWS_REGION}" \
    --db-parameter-group-name "${DB_PARAMETER_GROUP_NAME}" >/dev/null 2>&1 || true
}

delete_subnet_group_if_unused() {
  local in_use=""
  in_use="$(aws rds describe-db-instances \
    --region "${AWS_REGION}" \
    --query "DBInstances[?DBSubnetGroup.DBSubnetGroupName==\`${DB_SUBNET_GROUP_NAME}\`].DBInstanceIdentifier" \
    --output text 2>/dev/null || true)"

  if [[ -n "${in_use}" && "${in_use}" != "None" ]]; then
    echo "O subnet group ${DB_SUBNET_GROUP_NAME} ainda esta em uso por ${in_use}. O cleanup foi bloqueado." >&2
    exit 1
  fi

  aws rds delete-db-subnet-group \
    --region "${AWS_REGION}" \
    --db-subnet-group-name "${DB_SUBNET_GROUP_NAME}" >/dev/null 2>&1 || true
}

delete_security_group_if_unused() {
  local sg_id="$1"
  local in_use=""
  local network_interfaces=""

  in_use="$(aws rds describe-db-instances \
    --region "${AWS_REGION}" \
    --query "DBInstances[?length(VpcSecurityGroups[?VpcSecurityGroupId==\`${sg_id}\`]) > \`0\`].DBInstanceIdentifier" \
    --output text 2>/dev/null || true)"

  if [[ -n "${in_use}" && "${in_use}" != "None" ]]; then
    echo "O security group ${sg_id} ainda esta em uso por instancias RDS (${in_use}). O cleanup foi bloqueado." >&2
    exit 1
  fi

  network_interfaces="$(aws ec2 describe-network-interfaces \
    --region "${AWS_REGION}" \
    --filters "Name=group-id,Values=${sg_id}" \
    --query 'NetworkInterfaces[].NetworkInterfaceId' \
    --output text 2>/dev/null || true)"

  if [[ -n "${network_interfaces}" && "${network_interfaces}" != "None" ]]; then
    echo "O security group ${sg_id} ainda esta em uso por interfaces de rede (${network_interfaces}). O cleanup foi bloqueado." >&2
    exit 1
  fi

  aws ec2 delete-security-group --region "${AWS_REGION}" --group-id "${sg_id}" >/dev/null 2>&1 || true
}

cleanup_named_vpc_if_safe() {
  local vpc_ids=""
  local vpc_id=""
  local subnet_ids=""
  local association_ids=""
  local route_table_ids=""
  local igw_ids=""

  vpc_ids="$(aws ec2 describe-vpcs \
    --region "${AWS_REGION}" \
    --filters "Name=tag:Name,Values=${SHARED_INFRA_NAME}-vpc" \
    --query 'Vpcs[].VpcId' \
    --output text 2>/dev/null || true)"

  for vpc_id in ${vpc_ids}; do
    if [[ -z "${vpc_id}" || "${vpc_id}" == "None" ]]; then
      continue
    fi

    ensure_vpc_is_not_shared "${vpc_id}" "${db_sg_id:-}"

    subnet_ids="$(aws ec2 describe-subnets \
      --region "${AWS_REGION}" \
      --filters "Name=vpc-id,Values=${vpc_id}" \
      --query 'Subnets[].SubnetId' \
      --output text 2>/dev/null || true)"

    for association_id in $(aws ec2 describe-route-tables \
      --region "${AWS_REGION}" \
      --filters "Name=vpc-id,Values=${vpc_id}" \
      --query 'RouteTables[].Associations[?Main!=`true`].RouteTableAssociationId' \
      --output text 2>/dev/null || true); do
      [[ -n "${association_id}" && "${association_id}" != "None" ]] || continue
      aws ec2 disassociate-route-table --region "${AWS_REGION}" --association-id "${association_id}" >/dev/null 2>&1 || true
    done

    for route_table_ids in $(aws ec2 describe-route-tables \
      --region "${AWS_REGION}" \
      --filters "Name=vpc-id,Values=${vpc_id}" \
      --query 'RouteTables[?length(Associations[?Main==`true`])==`0`].RouteTableId' \
      --output text 2>/dev/null || true); do
      [[ -n "${route_table_ids}" && "${route_table_ids}" != "None" ]] || continue
      aws ec2 delete-route-table --region "${AWS_REGION}" --route-table-id "${route_table_ids}" >/dev/null 2>&1 || true
    done

    for igw_ids in $(aws ec2 describe-internet-gateways \
      --region "${AWS_REGION}" \
      --filters "Name=attachment.vpc-id,Values=${vpc_id}" \
      --query 'InternetGateways[].InternetGatewayId' \
      --output text 2>/dev/null || true); do
      [[ -n "${igw_ids}" && "${igw_ids}" != "None" ]] || continue
      aws ec2 detach-internet-gateway --region "${AWS_REGION}" --internet-gateway-id "${igw_ids}" --vpc-id "${vpc_id}" >/dev/null 2>&1 || true
      aws ec2 delete-internet-gateway --region "${AWS_REGION}" --internet-gateway-id "${igw_ids}" >/dev/null 2>&1 || true
    done

    for subnet_id in ${subnet_ids}; do
      [[ -n "${subnet_id}" && "${subnet_id}" != "None" ]] || continue
      aws ec2 delete-subnet --region "${AWS_REGION}" --subnet-id "${subnet_id}" >/dev/null 2>&1 || true
    done

    aws ec2 delete-vpc --region "${AWS_REGION}" --vpc-id "${vpc_id}" >/dev/null 2>&1 || true
  done
}

cleanup_bucket_if_safe() {
  local bucket_name="$1"
  local keys=""
  local key=""
  local delete_payload=""

  keys="$(aws s3api list-object-versions \
    --region "${TF_STATE_REGION}" \
    --bucket "${bucket_name}" \
    --query 'concat(Versions[].Key, DeleteMarkers[].Key)' \
    --output text 2>/dev/null || true)"

  if [[ -z "${keys}" || "${keys}" == "None" ]]; then
    aws s3api delete-bucket --region "${TF_STATE_REGION}" --bucket "${bucket_name}" >/dev/null 2>&1 || true
    return
  fi

  for key in ${keys}; do
    if [[ "${key}" != "${TF_STATE_KEY}" ]]; then
      log "Bucket ${bucket_name} mantido porque ainda contem objeto externo ao state deste projeto: ${key}"
      return
    fi
  done

  require_cmd jq

  delete_payload="$(aws s3api list-object-versions \
    --region "${TF_STATE_REGION}" \
    --bucket "${bucket_name}" \
    --output json | jq -c --arg key "${TF_STATE_KEY}" '
      {
        Objects: (
          [
            (.Versions[]? | select(.Key == $key) | {Key: .Key, VersionId: .VersionId}),
            (.DeleteMarkers[]? | select(.Key == $key) | {Key: .Key, VersionId: .VersionId})
          ] | flatten
        ),
        Quiet: true
      }
    ')"

  if [[ "$(jq '.Objects | length' <<<"${delete_payload}")" -gt 0 ]]; then
    aws s3api delete-objects \
      --region "${TF_STATE_REGION}" \
      --bucket "${bucket_name}" \
      --delete "${delete_payload}" >/dev/null 2>&1 || true
  fi

  aws s3api delete-bucket --region "${TF_STATE_REGION}" --bucket "${bucket_name}" >/dev/null 2>&1 || true
}

require_cmd aws
require_non_empty "${AWS_REGION}" "AWS_REGION"

bucket_name="$(resolve_backend_bucket)"
db_sg_id=""

if bucket_exists "${bucket_name}" && remote_state_exists "${bucket_name}"; then
  echo "O state remoto ${bucket_name}/${TF_STATE_KEY} existe. Use o workflow de destroy normal; o cleanup de orfaos foi bloqueado." >&2
  exit 1
fi

if db_exists; then
  db_sg_id="$(db_security_group_id)"
  ensure_vpc_is_not_shared "$(db_vpc_id)" "${db_sg_id}"
  log "Desabilitando deletion protection da instancia ${DB_IDENTIFIER}"
  disable_db_deletion_protection
  log "Removendo instancia RDS ${DB_IDENTIFIER}"
  delete_db_instance
  aws rds wait db-instance-deleted --region "${AWS_REGION}" --db-instance-identifier "${DB_IDENTIFIER}"
fi

delete_parameter_group_if_unused
delete_subnet_group_if_unused

if [[ -z "${db_sg_id}" ]]; then
  db_sg_id="$(aws ec2 describe-security-groups \
    --region "${AWS_REGION}" \
    --filters "Name=group-name,Values=${DB_IDENTIFIER}-sg" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || true)"
fi

if [[ -n "${db_sg_id}" && "${db_sg_id}" != "None" ]]; then
  delete_security_group_if_unused "${db_sg_id}"
fi

cleanup_named_vpc_if_safe

if bucket_exists "${bucket_name}"; then
  cleanup_bucket_if_safe "${bucket_name}"
fi
