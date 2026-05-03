# AGENTS.md

## Contexto

Este repositório gerencia a infraestrutura AWS/Terraform da base PostgreSQL da Oficina e também concentra scripts operacionais do banco.

Stack e componentes atuais do projeto:

- Terraform com root module em `terraform/environments/lab`
- Módulos próprios em `terraform/modules/network`, `terraform/modules/rds-postgres` e `terraform/modules/terraform_shared_data_bucket`
- Scripts Bash em `scripts/` para `apply`, `destroy`, cleanup, migrations Flyway, import SQL, bootstrap do usuário da aplicação e publicação de secret no cluster
- SQL de migrations em `sql/migrations`
- Seed de laboratório em `sql/import.sql`
- Documentação operacional em `README.md` e `docs/github-actions.md`

Este repositório faz parte de uma suíte maior. Assuma que, quando presentes na mesma raiz deste diretório, os repositórios irmãos mais relevantes são:

- `../oficina-app`
- `../oficina-auth-lambda`
- `../oficina-infra-k8s`

Quando esses repositórios estiverem disponíveis, eles devem ser consultados para manter consistência de nomes e contratos compartilhados, especialmente:

- nomes de environments
- nomes de secrets
- nomes de variáveis de ambiente
- nomes de recursos compartilhados do lab
- schemas, credenciais e convenções de integração entre aplicação, lambda e banco

## Diretrizes Gerais

- Preserve a arquitetura atual baseada em Terraform, scripts operacionais e migrations SQL.
- Prefira mudanças pequenas, objetivas e compatíveis com o padrão já existente no repositório.
- Não introduza novas ferramentas, módulos ou dependências sem necessidade clara.
- Mantenha alinhamento com as convenções já descritas no `README.md`, principalmente para `shared_infra_name`, `eks_cluster_name`, bucket de state e identificadores do RDS.
- Ao mexer em recursos compartilhados do laboratório, preserve a lógica atual de reuso antes de criar recursos novos.
- Não quebre o fluxo atual dos workflows GitHub Actions nem os scripts usados por CI/deploy.
- Ao alterar SQL, preserve a separação entre migration versionada em `sql/migrations` e seed de laboratório em `sql/import.sql`.
- Quando houver dúvida sobre nomes ou contratos que precisam bater entre serviços e infra, consulte primeiro `../oficina-app`, `../oficina-auth-lambda` e `../oficina-infra-k8s`.

## Implementação

- Em Terraform, siga o padrão existente de variáveis, `locals`, `checks`, `outputs` e composição de módulos.
- Prefira reaproveitar módulos e convenções já presentes em vez de duplicar lógica.
- Em scripts Bash, mantenha `set -euo pipefail`, validações explícitas, mensagens objetivas e compatibilidade com execução local e CI.
- Em migrations Flyway, siga o padrão `V<numero>__<descricao>.sql` e trate mudanças de schema de forma incremental.
- Evite acoplar mudanças locais a valores hardcoded quando o projeto já deriva nomes por variáveis, outputs ou secrets.
- Se houver erro simples, warning simples ou ajuste mecânico evidente dentro do escopo da tarefa, resolva junto em vez de deixar pendência.

## Validação

Antes de encerrar uma alteração, execute a validação compatível com o impacto da mudança:

- `terraform fmt -check -recursive terraform`
- `terraform -chdir=terraform/environments/lab validate` quando houver mudança em Terraform
- `find scripts -type f -name '*.sh' -print0 | xargs -0 bash -n` quando houver mudança em scripts
- validação das migrations ou do SQL alterado quando houver mudança em `sql/`

Se alguma verificação depender de credenciais, backend inicializado, AWS, Docker ou outras dependências não disponíveis no ambiente, registre isso claramente na resposta final.

## Versionamento e Operação

Este projeto depende de comandos explícitos para validar infraestrutura, operar o banco e registrar mudanças no Git.

Comandos relevantes de Terraform:

- `terraform -chdir=terraform/environments/lab init`
- `terraform -chdir=terraform/environments/lab plan -var-file=terraform.tfvars`
- `terraform -chdir=terraform/environments/lab apply -var-file=terraform.tfvars`
- `terraform fmt -check -recursive terraform`
- `terraform -chdir=terraform/environments/lab validate`

Comandos relevantes de scripts:

- `./scripts/actions/ci-terraform.sh`
- `./scripts/actions/ci-deploy.sh`
- `./scripts/manual/run-db-migrations.sh migrate`
- `./scripts/manual/run-rds-import.sh`
- `./scripts/manual/bootstrap-app-user.sh`
- `./scripts/manual/apply-k8s-secret.sh`

## Commits

Sempre que houver alterações no repositório ao final da tarefa, crie um commit antes de encerrar a resposta.

Antes de criar o commit:

- verifique o estado do repositório com `git status --short`
- adicione ao Git os arquivos novos criados no escopo da tarefa com `git add <arquivo>`
- faça stage dos arquivos alterados da tarefa com `git add <arquivo>` ou `git add <diretorio>`
- revise se não há mudanças alheias já staged antes de prosseguir

Ao criar o commit:

- use `git commit -m "<tipo>: <descricao em portugues>"`
- use mensagens em português seguindo Conventional Commits
- prefira mensagens curtas, objetivas e diretamente relacionadas à alteração
- faça commit apenas dos arquivos relacionados à tarefa atual
- nunca inclua no commit mudanças alheias que já estavam no worktree ou já estavam staged por outra tarefa

Exemplos válidos:

- `feat: adiciona automação de secret do banco`
- `fix: corrige validação do backend terraform`
- `docs: adiciona instruções operacionais do repositório`
- `chore: ajusta script de migrations`

## Restrições Práticas

- Não remova proteções destrutivas existentes do Terraform e dos scripts sem justificativa técnica explícita.
- Não altere desnecessariamente a estratégia de reuso da VPC, subnets, security groups e bucket compartilhado.
- Não trate `sql/import.sql` como migration versionada.
- Não presuma acesso irrestrito à AWS, ao backend remoto ou ao cluster Kubernetes durante desenvolvimento local.
- Não ignore falhas simples de lint, shell, formatação ou validação dentro do escopo da mudança.
