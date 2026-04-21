# GitHub Actions

O repositório usa a mesma família de workflows do `oficina-infra-k8s`, mas operando apenas sobre a infraestrutura do banco:

- `./.github/workflows/deploy-lab.yml`
- `./.github/workflows/terraform-apply-lab.yml`
- `./.github/workflows/terraform-destroy-lab.yml`
- `./.github/workflows/cleanup-orphan-db-lab.yml`

## Gatilho

- `push` na `main` para deploy pelo `Deploy Lab`
- `push` em outras branches para validação e abertura automática de PR para `main`
- `workflow_dispatch` para execução manual

Todos usam o GitHub Environment `lab`.

Os jobs/workflows que alteram infraestrutura compartilham o mesmo grupo de `concurrency`, então `deploy`, `apply`, `destroy` e `cleanup` não executam em paralelo no mesmo ambiente.

No `Deploy Lab`, pushes em branches diferentes de `main` executam validações de shell e Terraform. Quando elas passam, o workflow cria ou atualiza automaticamente um pull request da branch atual para `main`. O deploy de infraestrutura continua limitado a push na `main` ou execução manual por `workflow_dispatch`.

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
- `DB_SSLMODE`: default `require`
- `RUN_DB_MIGRATIONS`: default `true`
- `RUN_DB_IMPORT`: default `true`
- `DB_IMPORT_FILE`: default `sql/import.sql`
- `FLYWAY_DOCKER_IMAGE`: default `redgate/flyway:12.4-alpine`
- `FLYWAY_BASELINE_ON_MIGRATE`: default `true`
- `AUTO_ALLOW_CI_RUNNER_CIDR`: default `true`; adiciona o IPv4 publico do runner atual em `DB_ALLOWED_CIDR_BLOCKS` durante o deploy quando migrations, import ou bootstrap precisam conectar no RDS
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

## Migrations do banco

O workflow `Deploy Lab` executa `scripts/run-db-migrations.sh migrate` depois do `terraform apply` e depois do bootstrap opcional do usuário da aplicação. Depois das migrations, quando `RUN_DB_IMPORT=true`, executa `scripts/run-rds-import.sh` para aplicar o seed de laboratorio.

Por padrão, `RUN_DB_MIGRATIONS=true`. O script usa Flyway para aplicar os arquivos em `sql/migrations` e registra o histórico em `public.flyway_schema_history`.

Como o Flyway roda no runner do GitHub Actions, o deploy adiciona automaticamente o IPv4 publico do runner atual como um CIDR `/32` permitido no security group do RDS quando `AUTO_ALLOW_CI_RUNNER_CIDR=true`. CIDRs definidos em `DB_ALLOWED_CIDR_BLOCKS` sao preservados.

Quando o schema já existe porque foi criado anteriormente pelo Hibernate/Quarkus da aplicação principal, `FLYWAY_BASELINE_ON_MIGRATE=true` cria um baseline na versão `1` e ainda aplica as próximas migrations, começando pela `V2__create_auth_schema.sql`. Em bancos vazios, a `V1__create_app_schema.sql` e a `V2__create_auth_schema.sql` são aplicadas normalmente.

A carga `sql/import.sql` e seed de laboratório e roda automaticamente no deploy quando `RUN_DB_IMPORT=true`. O arquivo usa upserts para poder ser reexecutado no ambiente lab.

## Guardas destrutivas

Antes de `destroy`, o workflow bloqueia a execução quando:

- o subnet group do banco ainda está sendo usado por outro RDS
- o security group do banco ainda está sendo usado por outro RDS
- a VPC gerenciada por este repo ainda está em uso por clusters EKS, outros RDS ou ENIs externos ao banco
- o bucket compartilhado contém objetos fora da key de state deste projeto

O workflow `Cleanup Orphan DB Lab Infra` bloqueia quando encontra state remoto existente, porque nesse caso o caminho correto é o destroy normal. Quando encontra dependências externas na infraestrutura compartilhada, ele preserva esses recursos e continua removendo apenas o que for exclusivo do banco.

No `Deploy Lab` e no `Terraform Apply Lab`, se o state remoto ainda não existir mas houver resíduos nomeados do banco, o script executa automaticamente um cleanup limitado aos recursos do banco antes de tentar o `apply`.
