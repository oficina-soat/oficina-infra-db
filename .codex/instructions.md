# Instruções para agentes Codex

Este projeto gerencia infraestrutura AWS/Terraform da base PostgreSQL da Oficina, além de scripts operacionais em Bash e migrations/seed SQL.

## Regras gerais

- Prefira comandos reais de validação em vez de inferências.
- Não assuma que credenciais AWS, backend remoto do Terraform, Docker, Flyway ou acesso ao banco estejam disponíveis.
- Quando alterar Terraform, execute pelo menos formatação e validação compatíveis.
- Quando alterar scripts, execute validação sintática compatível.
- Quando alterar SQL, preserve a separação entre migrations em `sql/migrations` e seed de laboratório em `sql/import.sql`.
- Quando a tarefa depender de AWS, valide primeiro se o acesso está disponível com AWS CLI.
- Antes de encerrar, confira o estado do Git e prepare o commit explicitamente.

## Terraform

Comandos preferenciais:

```bash
terraform -chdir=terraform/environments/lab init
terraform fmt -check -recursive terraform
terraform -chdir=terraform/environments/lab validate
terraform -chdir=terraform/environments/lab plan -var-file=terraform.tfvars
```

Use `terraform fmt -check -recursive terraform` para validação rápida de formatação.

Use `terraform -chdir=terraform/environments/lab validate` quando a alteração afetar módulos, variáveis, outputs, providers, checks ou root module.

Use `terraform -chdir=terraform/environments/lab plan -var-file=terraform.tfvars` quando precisar validar impacto funcional e o ambiente estiver preparado.

Não execute `terraform apply` ou `terraform destroy` sem necessidade explícita da tarefa e sem revisar o contexto do ambiente.

## Scripts Bash

Use validação sintática quando houver mudanças em scripts:

```bash
bash -n scripts/*.sh
```

Scripts operacionais relevantes:

```bash
./scripts/ci-terraform.sh
./scripts/ci-deploy.sh
./scripts/run-db-migrations.sh migrate
./scripts/run-rds-import.sh
./scripts/bootstrap-app-user.sh
./scripts/apply-k8s-secret.sh
```

## AWS

Use AWS CLI quando precisar validar ambiente remoto:

```bash
aws sts get-caller-identity
```

Prefira comandos AWS de leitura para validar RDS, Secrets Manager, S3, EKS e outros recursos relacionados ao projeto.

## Git

Ao concluir alterações no escopo da tarefa, prepare o commit explicitamente com:

```bash
git status --short
git add <arquivos-da-tarefa>
git commit -m "<tipo>: <resumo>"
```

Prefira mensagens curtas em português seguindo Conventional Commits e não inclua mudanças alheias já presentes no worktree.
