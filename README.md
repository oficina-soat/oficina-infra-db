# oficina-db-infra

Infraestrutura Terraform da base PostgreSQL da Oficina com baseline voltado para produção enxuta, priorizando baixo custo para laboratório acadêmico.

O projeto provisiona um Amazon RDS PostgreSQL com:

- `db.t4g.micro` e `Single-AZ` por default para reduzir custo fixo
- backups automáticos, janela de backup e janela de manutenção
- deletion protection, snapshot final e `prevent_destroy`
- senha master gerenciada pelo AWS Secrets Manager
- parameter group com SSL forçado e logs de queries lentas
- autoscaling de storage habilitado
- monitoramento pago opcional: log exports, Enhanced Monitoring, Performance Insights e alarmes

## O que este projeto não cria

- VPC, sub-redes e rotas
- SNS topics para alarmes
- cluster Kubernetes
- migrations de schema da aplicação

## Pré-requisitos

- Terraform `>= 1.6`
- AWS CLI autenticada
- bucket S3 e tabela DynamoDB apenas se quiser backend remoto
- VPC existente com pelo menos duas sub-redes já usadas pelo cluster; no laboratório atual, o projeto `oficina-infra-k8s` cria apenas duas sub-redes públicas
- `kubectl`, se quiser publicar o secret da aplicação no cluster
- `psql`, se quiser executar bootstrap administrativo no banco

## Estrutura

O repositório segue um layout em diretórios:

- `terraform/modules/rds-postgres`: módulo reutilizável com os recursos AWS do banco
- `terraform/environments/lab`: root module do ambiente atual, com provider, inputs e outputs
- `scripts/`: automações operacionais que leem outputs do root module

## State do Terraform

Por default, o projeto usa backend local. Sem bucket S3, basta inicializar normalmente:

```bash
terraform -chdir=terraform/environments/lab init
```

Se quiser backend remoto em `s3`, gere dois arquivos locais a partir dos exemplos:

```bash
cp terraform/environments/lab/backend.tf.example terraform/environments/lab/backend.tf
cp terraform/environments/lab/backend.hcl.example terraform/environments/lab/backend.hcl
```

Depois ajuste `backend.hcl` e inicialize:

```bash
terraform -chdir=terraform/environments/lab init -reconfigure -backend-config=backend.hcl
```

## Configuração

Use `terraform.tfvars.example` como base:

```bash
cp terraform/environments/lab/terraform.tfvars.example terraform/environments/lab/terraform.tfvars
```

Variáveis principais:

- `eks_cluster_name`: nome do cluster criado pelo projeto `oficina-infra-k8s`; quando informado, este projeto descobre `vpc_id`, `subnet_ids` e adiciona o security group primário do EKS automaticamente
- `db_identifier`: identificador do RDS
- `db_name`: nome do banco
- `db_username`: usuário administrador inicial; não use este usuário na aplicação
- `instance_class`: default `db.t4g.micro`
- `allocated_storage` e `max_allocated_storage`: capacidade inicial e autoscaling
- `vpc_id` e `subnet_ids`: rede onde o RDS será provisionado; no laboratório, podem ser omitidos se `eks_cluster_name` estiver definido
- `allowed_security_group_ids`: origem real da aplicação; no laboratório, pode ser omitido se você aceitar o security group primário do EKS como origem
- `allowed_cidr_blocks`: CIDRs externos autorizados a acessar a porta `5432`; para acesso local, informe seu IP público com `/32`
- `final_snapshot_identifier`: snapshot final obrigatório ao destruir
- `multi_az`: deixe `false` no laboratório e avalie `true` apenas se disponibilidade for mais importante que custo
- `monitoring_interval`, `performance_insights_enabled`, `enabled_cloudwatch_logs_exports` e `create_alarms`: opcionais para observabilidade paga
- o baseline do laboratório limita o autoscaling de storage a `40 GB` e evita logs verbosos de conexão/desconexão

Com o `oficina-infra-k8s` atual, o caminho padrão de laboratório fica:

- subir a rede e o cluster pelo repositório `oficina-infra-k8s`
- informar apenas `eks_cluster_name` neste repositório
- manter `publicly_accessible = true` se precisar conectar da sua máquina e preencher `allowed_cidr_blocks` com seu IP público

## Aplicação da infraestrutura

```bash
terraform -chdir=terraform/environments/lab plan -var-file=terraform.tfvars
terraform -chdir=terraform/environments/lab apply -var-file=terraform.tfvars
```

## Deploy com GitHub Actions

O workflow [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml) executa em `push` para a branch `main`.

O job usa o GitHub Environment `hml` para centralizar `vars` e `secrets` e faz o acesso à AWS com credenciais clássicas do AWS CLI via `aws-actions/configure-aws-credentials`.

Valores esperados no Environment:

- `AWS_REGION`: região da AWS usada pelo provider e pela autenticação do runner
- `AWS_ACCESS_KEY_ID`: credencial AWS em `secrets`
- `AWS_SECRET_ACCESS_KEY`: credencial AWS em `secrets`
- `AWS_SESSION_TOKEN`: opcional, mas necessário se o laboratório entregar credenciais temporárias
- `TERRAFORM_VERSION`: opcional; se omitido, o workflow usa `1.6.6`
- `TERRAFORM_ROOT_DIR`: opcional; se omitido, o workflow usa `terraform/environments/lab`

As variáveis `TF_BACKEND_*` são opcionais e só precisam existir se você quiser usar backend remoto em `s3` no GitHub Actions:

- `TF_BACKEND_BUCKET`: bucket S3 do backend remoto do Terraform
- `TF_BACKEND_KEY`: chave do state dentro do bucket
- `TF_BACKEND_DYNAMODB_TABLE`: tabela DynamoDB de lock do state
- `TF_BACKEND_REGION`: opcional; se omitido, usa `AWS_REGION`
- `TF_BACKEND_ENCRYPT`: opcional
- `TF_BACKEND_KMS_KEY_ID`: opcional

As entradas do Terraform devem ser publicadas como `TF_VAR_*` no próprio Environment:

- valores sensíveis em `secrets`, por exemplo `TF_VAR_DB_USERNAME`
- valores não sensíveis em `vars`, por exemplo `TF_VAR_REGION`, `TF_VAR_EKS_CLUSTER_NAME` e `TF_VAR_DB_IDENTIFIER`
- listas e mapas podem ser enviados em JSON, por exemplo `TF_VAR_SUBNET_IDS=["subnet-a","subnet-b"]`

O workflow exporta automaticamente para o runner todas as chaves com prefixo `AWS_`, `TF_BACKEND_`, `TF_VAR_` e `TERRAFORM_` vindas do Environment selecionado. Antes de chamar o Terraform, ele converte o trecho após `TF_VAR_` para minúsculas, então `TF_VAR_DB_IDENTIFIER` vira `TF_VAR_db_identifier`.

Sem `TF_BACKEND_*`, o runner usa backend local apenas durante aquela execução. Para deploys recorrentes, mantenha o backend remoto configurado para preservar o state entre runs.

Se o laboratório recriar as credenciais a cada nova sessão, atualize os `secrets` `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e, quando houver, `AWS_SESSION_TOKEN` antes do merge que vai disparar o deploy.

Saídas principais:

- `db_endpoint`
- `db_port`
- `db_name`
- `db_master_user_secret_arn`
- `db_alarm_names`

Por default, `db_alarm_names` vira uma lista vazia porque alarmes ficam desabilitados para manter o custo mínimo.

## Fluxo de credenciais

O usuário master do RDS fica no AWS Secrets Manager. Esse secret é apenas administrativo.

Para criar ou atualizar um usuário próprio da aplicação:

```bash
STORE_IN_SECRETS_MANAGER=true \
APP_SECRET_NAME="oficina/prod/database/app" \
./scripts/bootstrap-app-user.sh
```

O script:

- lê a credencial master do output `db_master_user_secret_arn`
- cria ou atualiza o role `oficina_app`
- aplica grants de runtime na schema `public`
- opcionalmente grava a credencial da aplicação no Secrets Manager

## Publicação do secret no Kubernetes

Publique no cluster apenas a credencial da aplicação, nunca a senha master:

```bash
DB_SECRET_ARN="oficina/prod/database/app" \
./scripts/apply-k8s-secret.sh
```

O script suporta `OUTPUT_ONLY=true` para apenas renderizar o manifesto.

## Schema e carga de dados

`sql/import.sql` voltou a conter uma carga inicial para laboratório e demonstração.

- o arquivo popula usuários, clientes, veículos, ordens de serviço, peças e serviços
- o processo não é idempotente e pode falhar se os dados já existirem
- para uso realmente produtivo, prefira migrations versionadas e seeds revisados por ambiente

Se ainda precisar executar SQL administrativo:

```bash
DB_SECRET_ARN="oficina/prod/database/app" \
IMPORT_FILE="sql/import.sql" \
./scripts/run-rds-import.sh
```

## Validações recomendadas

```bash
terraform fmt -check -recursive terraform
terraform -chdir=terraform/environments/lab validate
bash -n scripts/*.sh
```

## Perfil de custo

Defaults pensados para laboratório acadêmico:

- `db.t4g.micro`
- `Single-AZ`
- `20 GB` gp3 com autoscaling limitado a `40 GB`
- `7 dias` de backup
- sem alarmes
- sem log export para CloudWatch
- sem Enhanced Monitoring
- sem Performance Insights

Esses defaults preservam:

- criptografia em repouso
- acesso público restrito por security group/CIDR
- proteção contra delete
- snapshot final
- secret master gerenciada
