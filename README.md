# oficina-db-infra

## Propósito

Infraestrutura AWS/Terraform da base PostgreSQL da Oficina. Este repositório provisiona ou reutiliza a rede do laboratório, cria o RDS, gerencia parâmetros e segurança do banco, executa migrations/seed e publica o secret Kubernetes usado pelo `oficina-app`.

## Tecnologias utilizadas

- Terraform `>= 1.6`
- AWS Provider para VPC, RDS PostgreSQL, Secrets Manager, S3, CloudWatch e IAM
- PostgreSQL 16 para operações e imagem auxiliar `postgres:16-alpine`
- Flyway 12.4 para migrations SQL
- Bash, AWS CLI, Docker e kubectl
- GitHub Actions para deploy, destroy e promoção `develop -> main`
- SQL versionado em `sql/migrations` e seed de laboratório em `sql/import.sql`

## Deploy e teste da suíte

O deploy integrado não deve começar por este repositório. Execute o procedimento principal pelo repositório `../oficina-infra-k8s`:

```text
oficina-infra-k8s -> Actions -> Deploy Lab -> Run workflow
```

O `Deploy Lab` do `oficina-infra-k8s` aplica a infraestrutura AWS e Kubernetes e dispara o `deploy-lab.yml` deste repositório. Este deploy aplica RDS, migrations e seed e, ao final, dispara automaticamente o `deploy-lambda-lab.yml` do `oficina-auth-lambda` e o `deploy-app-lab.yml` do `oficina-app`. Use o `Deploy Lab` deste repositório diretamente apenas para manutenção específica do banco.

Depois que todos os workflows terminarem, o teste principal deve ser executado no repositório `../oficina-app`:

```bash
cd ../oficina-app
MODO_ACESSO=aws ./scripts/validar-metricas-paineis.sh
```

Infraestrutura AWS/Terraform da base PostgreSQL da Oficina.

O repositório foi alinhado com `oficina-infra-k8s` para usar os mesmos nomes de infra compartilhada do laboratório e a mesma família de GitHub Actions, mas continua independente:

- se a infra compartilhada do lab já existir, este projeto a reutiliza
- se ela não existir, este projeto cria o que precisa para o banco subir
- recursos compartilhados fora do state deste repo não são recriados nem destruídos

## O que este projeto gerencia

- Amazon RDS PostgreSQL
- security group, subnet group e parameter group do banco
- VPC/subnets do lab quando a rede compartilhada ainda não existir
- bucket S3 compartilhado do Terraform quando ele precisar ser criado por este state

## Swagger, OpenAPI e Postman

Este repositório não expõe API HTTP própria; ele entrega banco, migrations e secrets consumidos pelas APIs da suíte. Use os links abaixo para a documentação das APIs que dependem desta infraestrutura:

- API principal local: `http://localhost:8080/q/swagger-ui/`
- OpenAPI principal local: `http://localhost:8080/q/openapi`
- API principal no lab: `<oficina_app_public_base_url>/q/swagger-ui/`
- Auth/JWKS no lab: `<OFICINA_AUTH_ISSUER>/.well-known/openid-configuration` e `<OFICINA_AUTH_ISSUER>/.well-known/jwks.json`
- Não há coleção Postman versionada neste repositório; importe o OpenAPI do `oficina-app` no Postman quando necessário.

## Diagrama de serviços

```mermaid
flowchart LR
  github[GitHub Actions<br/>deploy-lab / destroy-lab]
  local[Operador local<br/>scripts/manual]
  terraform[Terraform<br/>terraform/environments/lab]

  github --> terraform
  local --> terraform

  subgraph aws[AWS]
    state[(S3 bucket compartilhado<br/>state Terraform)]

    subgraph network[Rede do lab<br/>criada ou reutilizada]
      vpc[VPC eks-lab]
      igw[Internet Gateway]
      route[Route table publica]
      subnetA[Public subnet AZ A]
      subnetB[Public subnet AZ B]
      eksSg[Security groups do EKS<br/>descobertos por tag]
      cidrs[CIDRs permitidos<br/>allowed_cidr_blocks]
    end

    subgraph database[PostgreSQL gerenciado]
      dbSg[Security group do RDS<br/>porta 5432]
      subnetGroup[DB subnet group]
      parameterGroup[DB parameter group<br/>force_ssl / scram-sha-256]
      rds[(Amazon RDS PostgreSQL<br/>oficina-postgres-lab)]
      masterSecret[AWS Secrets Manager<br/>secret master gerado pelo RDS]
      appSecret[AWS Secrets Manager<br/>secret da aplicacao opcional]
    end

    subgraph observability[Observabilidade opcional]
      logGroups[CloudWatch Log Groups<br/>postgresql / upgrade]
      alarms[CloudWatch Alarms<br/>CPU / storage / memoria]
      monitoringRole[IAM role<br/>Enhanced Monitoring]
    end
  end

  subgraph eks[EKS compartilhado<br/>oficina-infra-k8s]
    k8sSecret[Kubernetes Secret<br/>oficina-database-env]
    oficinaApp[oficina-app]
  end

  subgraph consumers[Consumidores externos]
    authLambda[oficina-auth-lambda<br/>usa schema auth]
  end

  terraform --> state
  terraform --> vpc
  vpc --> igw
  igw --> route
  route --> subnetA
  route --> subnetB
  terraform --> dbSg
  terraform --> subnetGroup
  terraform --> parameterGroup
  terraform --> rds
  subnetA --> subnetGroup
  subnetB --> subnetGroup
  subnetGroup --> rds
  parameterGroup --> rds
  dbSg --> rds
  eksSg -->|ingress 5432| dbSg
  cidrs -->|ingress 5432| dbSg
  rds --> masterSecret
  rds --> logGroups
  monitoringRole --> rds
  rds --> alarms

  local -->|bootstrap-app-user.sh| appSecret
  github -->|ci-deploy.sh| appSecret
  appSecret -->|apply-k8s-secret.sh| k8sSecret
  masterSecret -->|run-db-migrations.sh| rds
  masterSecret -->|run-rds-import.sh| rds
  k8sSecret --> oficinaApp
  oficinaApp -->|PostgreSQL SSL 5432| dbSg
  authLambda -->|PostgreSQL SSL 5432| dbSg
```

## Convenções padronizadas com o repo k8s

- nome padrão da infra compartilhada: `eks-lab`
- bucket compartilhado: `tf-shared-<shared_infra_name>-<account-id>-<region>`
- chave default do state deste repo: `oficina/lab/database/terraform.tfstate`
- cluster EKS compartilhado esperado: `eks-lab`
- banco padrão: `oficina-postgres-lab`

## Estrutura

- `terraform/modules/network`: mesma convenção de rede do repo `oficina-infra-k8s`
- `terraform/modules/terraform_shared_data_bucket`: mesmo módulo de bucket compartilhado do repo `oficina-infra-k8s`
- `terraform/modules/rds-postgres`: módulo do banco
- `terraform/environments/lab`: root module do ambiente
- `scripts/actions/ci-terraform.sh`: apply/destroy com bootstrap e reuso do backend remoto
- `scripts/actions/ci-deploy.sh`: apply do Terraform, bootstrap opcional do usuário da aplicação, migrations Flyway e secret no cluster
- `scripts/manual/run-db-migrations.sh`: executa as migrations Flyway em `sql/migrations`
- `scripts/actions/cleanup-orphan-db.sh`: cleanup para recursos órfãos sem state remoto; remove resíduos do banco e preserva recursos compartilhados ainda em uso

## Comportamento de reuso e criação

O root module resolve a infraestrutura nesta ordem:

1. usa `vpc_id` e `subnet_ids` explícitos, se informados
2. tenta reutilizar a VPC nomeada como `<shared_infra_name>-vpc`, usando apenas subnets públicas tagueadas para o cluster EKS
3. se não encontrar a VPC e `create_network_if_missing=true`, cria uma rede nova com os mesmos nomes usados no repo k8s

Para acesso do EKS ao banco, o projeto tenta reutilizar security groups tagueados com `aws:eks:cluster-name=<eks_cluster_name>`. Se eles não existirem, informe `allowed_security_group_ids` ou `allowed_cidr_blocks`.

## Configuração local

Use o exemplo de variáveis:

```bash
cp terraform/environments/lab/terraform.tfvars.example terraform/environments/lab/terraform.tfvars
```

Campos principais:

- `shared_infra_name`: prefixo da infra compartilhada. Default `eks-lab`
- `eks_cluster_name`: nome do cluster EKS compartilhado. Default `eks-lab`
- `db_identifier`: default `oficina-postgres-lab`
- `create_network_if_missing`: cria a rede do lab se ela ainda não existir
- `vpc_id` e `subnet_ids`: forçam uso de rede específica; para acesso público ao RDS, use subnets públicas com rota para Internet Gateway
- `allowed_security_group_ids` e `allowed_cidr_blocks`: controlam quem acessa a porta `5432`
- `create_terraform_shared_data_bucket`: só deve ficar `true` quando este state for gerenciar o bucket compartilhado

## State do Terraform

Local:

```bash
terraform -chdir=terraform/environments/lab init
```

Remoto em S3:

```bash
cp terraform/environments/lab/backend.s3.tf.example terraform/environments/lab/backend.tf
cp terraform/environments/lab/backend.hcl.example terraform/environments/lab/backend.hcl
terraform -chdir=terraform/environments/lab init -reconfigure -backend-config=backend.hcl
```

Nos workflows do GitHub Actions, o script `scripts/actions/ci-terraform.sh` faz bootstrap local do bucket quando necessário, migra o state para S3 e reutiliza o bucket compartilhado quando ele já existir.

Quando o state remoto ainda não existe, mas resíduos nomeados do banco já existem, o workflow executa automaticamente um cleanup limitado ao banco antes do `apply`. Esse cleanup não remove VPC, subnets, route tables, internet gateway ou bucket compartilhado.

## Apply

```bash
terraform -chdir=terraform/environments/lab plan -var-file=terraform.tfvars
terraform -chdir=terraform/environments/lab apply -var-file=terraform.tfvars
```

## Destroy seguro

O baseline mantém `deletion_protection = true`.

Para destroy manual:

```bash
terraform -chdir=terraform/environments/lab destroy \
  -var-file=terraform.tfvars \
  -var='deletion_protection=false'
```

Nos GitHub Actions, o destroy faz verificações extras antes de continuar:

- bloqueia se subnet group ou security group do banco ainda estiverem em uso por outros RDS
- bloqueia se a VPC gerenciada por este repo ainda estiver em uso por clusters EKS, outros RDS ou ENIs externos ao banco
- bloqueia se o bucket compartilhado tiver objetos fora do state deste projeto

## GitHub Actions

Workflows disponíveis:

- `.github/workflows/deploy-lab.yml`
- `.github/workflows/open-pr-to-main.yml`
- `.github/workflows/destroy-lab.yml`

Os workflows que operam infraestrutura usam o GitHub Environment `lab` e um grupo de `concurrency` próprio do banco, mantendo a mesma organização do repo `oficina-infra-k8s`. O `Open PR To Main` roda separado do deploy, valida `develop` e cria ou atualiza o PR para `main`.

Ao final do `Deploy Lab` bem-sucedido, o workflow dispara os deploys assíncronos do `oficina-auth-lambda` para as duas Lambdas e do `oficina-app`, sem aguardar o resultado desses workflows.
Para o disparo cross-repo funcionar, configure `OFICINA_WORKFLOW_TOKEN` ou os tokens específicos descritos em [docs/github-actions.md](docs/github-actions.md) com permissão de escrita em Actions nos repositórios alvo.

Detalhes de variáveis e secrets: [docs/github-actions.md](docs/github-actions.md)

## Operações opcionais

Bootstrap do usuário da aplicação:

```bash
STORE_IN_SECRETS_MANAGER=true \
APP_SECRET_NAME="oficina/lab/database/app" \
./scripts/manual/bootstrap-app-user.sh
```

Migrations do schema:

```bash
./scripts/manual/run-db-migrations.sh migrate
```

O script usa o secret master do RDS exposto pelo Terraform quando `DB_SECRET_ARN` não é informado. Em CI ele usa a imagem Docker `redgate/flyway:12.4-alpine` quando o binário `flyway` não estiver instalado.

As migrations ficam em `sql/migrations`. A `V1__create_app_schema.sql` é a baseline das entidades JPA do `oficina-app`; a `V2__create_auth_schema.sql` cria as tabelas de autenticação usadas pelo lambda.

No `Deploy Lab`, o seed `sql/import.sql` roda depois das migrations quando `RUN_DB_IMPORT=true` (default). Ele usa upserts para poder ser reexecutado no ambiente lab.

Publicação do secret no cluster:

```bash
DB_SECRET_ARN="oficina/lab/database/app" \
EKS_CLUSTER_NAME="eks-lab" \
UPDATE_KUBECONFIG=true \
./scripts/manual/apply-k8s-secret.sh
```

O secret Kubernetes gerado usa `DB_SSLMODE=require` por padrão e publica a URL reativa do Quarkus com `sslmode=require`, compatível com o `rds.force_ssl=1` configurado no RDS.

Carga inicial:

```bash
./scripts/manual/run-db-migrations.sh migrate

DB_SECRET_ARN="oficina/lab/database/app" \
IMPORT_FILE="sql/import.sql" \
./scripts/manual/run-rds-import.sh
```

`sql/import.sql` é seed de laboratório, não migration. Ele assume que o Flyway já criou as tabelas.

## Validação local

```bash
terraform fmt -check -recursive terraform
terraform -chdir=terraform/environments/lab validate
find scripts -type f -name '*.sh' -print0 | xargs -0 bash -n
```
