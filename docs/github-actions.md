# GitHub Actions

O repositório usa a mesma família de workflows do `oficina-infra-k8s`, mas operando apenas sobre a infraestrutura do banco:

- `./.github/workflows/deploy-lab.yml`
- `./.github/workflows/terraform-apply-lab.yml`
- `./.github/workflows/terraform-destroy-lab.yml`
- `./.github/workflows/cleanup-orphan-db-lab.yml`

## Gatilho

- `push` em branch protegida para `Deploy Lab`
- `workflow_dispatch` para execução manual

Todos usam o GitHub Environment `lab`.

Todos os workflows que alteram infraestrutura compartilham o mesmo grupo de `concurrency`, então `deploy`, `apply`, `destroy` e `cleanup` não executam em paralelo no mesmo ambiente.

## Secrets obrigatórios

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN`

## Variables principais

- `AWS_REGION`
- `EKS_CLUSTER_NAME`
- `SHARED_INFRA_NAME`
- `DB_IDENTIFIER`
- `DB_NAME`
- `DB_USERNAME`
- `DB_INSTANCE_CLASS`
- `DB_ENGINE_VERSION`
- `DB_ALLOCATED_STORAGE`
- `DB_MAX_ALLOCATED_STORAGE`
- `DB_PUBLICLY_ACCESSIBLE`
- `DB_DELETION_PROTECTION`
- `DB_FINAL_SNAPSHOT_IDENTIFIER`
- `DB_ALLOWED_CIDR_BLOCKS`: lista JSON
- `DB_ALLOWED_SECURITY_GROUP_IDS`: lista JSON
- `DB_VPC_ID`
- `DB_SUBNET_IDS`: lista JSON
- `DB_CREATE_NETWORK_IF_MISSING`
- `DB_NETWORK_VPC_CIDR`
- `DB_AZS`: lista JSON
- `DB_PUBLIC_SUBNET_CIDRS`: lista JSON
- `CREATE_TERRAFORM_SHARED_DATA_BUCKET`
- `TERRAFORM_SHARED_DATA_BUCKET_NAME`
- `TERRAFORM_SHARED_DATA_BUCKET_FORCE_DESTROY`
- `TF_STATE_BUCKET`
- `TF_STATE_KEY`
- `TF_STATE_REGION`
- `TF_STATE_DYNAMODB_TABLE`
- `DB_CREATE_ALARMS`
- `DB_ENABLED_CLOUDWATCH_LOGS_EXPORTS`: lista JSON
- `DB_MONITORING_INTERVAL`
- `DB_PERFORMANCE_INSIGHTS_ENABLED`
- `DB_TAGS`: mapa JSON

## Variáveis de deploy opcional

Usadas só no `Deploy Lab`:

- `BOOTSTRAP_APP_USER`
- `APP_DB_USER`
- `APP_DB_ALLOW_SCHEMA_CHANGES`
- `STORE_APP_DB_SECRET_IN_SECRETS_MANAGER`
- `APP_DB_SECRET_NAME`
- `APP_DB_SECRET_KMS_KEY_ID`
- `APPLY_K8S_SECRET`
- `K8S_NAMESPACE`
- `K8S_SECRET_NAME`

Secret opcional do `Deploy Lab`:

- `APP_DB_PASSWORD`

## Estado remoto

Se `TF_STATE_BUCKET` não for informado, o script deriva automaticamente:

```text
tf-shared-<shared_infra_name>-<account-id>-<region>
```

O state default deste projeto é:

```text
oficina/lab/database/terraform.tfstate
```

Se o bucket ainda não existir, `scripts/ci-terraform.sh` faz bootstrap local, cria ou reaproveita o bucket compartilhado e migra o state para o backend remoto.

Se o bucket já existir fora do state deste projeto, o workflow o reutiliza sem tentar recriá-lo.

## Guardas destrutivas

Antes de `destroy`, o workflow bloqueia a execução quando:

- o subnet group do banco ainda está sendo usado por outro RDS
- o security group do banco ainda está sendo usado por outro RDS
- a VPC gerenciada por este repo ainda está em uso por clusters EKS, outros RDS ou ENIs externos ao banco
- o bucket compartilhado contém objetos fora da key de state deste projeto

O workflow `Cleanup Orphan DB Lab Infra` bloqueia quando encontra state remoto existente, porque nesse caso o caminho correto é o destroy normal. Quando encontra dependências externas na infraestrutura compartilhada, ele preserva esses recursos e continua removendo apenas o que for exclusivo do banco.

No `Deploy Lab` e no `Terraform Apply Lab`, se o state remoto ainda não existir mas houver resíduos nomeados do banco, o script executa automaticamente um cleanup limitado aos recursos do banco antes de tentar o `apply`.
