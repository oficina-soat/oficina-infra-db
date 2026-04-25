# Plano de Deploy para Minimizar o Tempo Total da Migração

## Princípio

A `V3` atual é destrutiva para consumidores antigos, porque:

- remove `ordem_de_servico.estado_atual`
- remove `os_item_peca.peca_nome`
- remove `os_item_servico.servico_nome`
- renomeia `papel.papel` para `papel.nome`

Como o banco é usado por `lambda` e `aplicação`, o rollout mais rápido e seguro não é um deploy único. O melhor caminho é:

`expand -> switch -> contract`

## Estrategia

### 1. Fase `Expand`

Criar uma migration compatível com código antigo e novo.

Essa fase deve:

- criar tabelas de domínio
- amarrar sequences ao schema
- criar FKs faltantes
- criar índices novos
- fazer backfill do histórico de estados
- manter colunas antigas ainda disponíveis
- adicionar mecanismos temporários de compatibilidade, se necessário

### 2. Fase `Switch`

Publicar lambda e aplicação já adaptados ao novo modelo.

Ambos passam a:

- derivar o estado atual a partir do último evento em `estado_ordem_servico`
- parar de depender de `peca_nome` e `servico_nome`
- usar `papel.nome`
- escrever transições de status no histórico

### 3. Fase `Contract`

Depois que app e lambda estiverem estabilizados, aplicar uma migration final removendo legado.

Essa fase remove:

- `ordem_de_servico.estado_atual`
- `os_item_peca.peca_nome`
- `os_item_servico.servico_nome`
- compatibilidades temporárias
- nomes e estruturas antigas que só existiam para transição

## Plano Proposto

### Etapa 1: Separar a `V3` atual

A `V3` atual deve ser dividida em duas migrations:

#### `V3_expand`

Inclui somente mudanças aditivas e compatíveis:

- criação das tabelas de domínio
- criação das novas FKs
- criação dos índices
- vínculo das sequences com `DEFAULT nextval(...)` e `OWNED BY`
- backfill do histórico com base em `estado_atual`
- constraints novas que não quebrem consumidores atuais
- manutenção das colunas antigas

#### `V4_contract`

Inclui apenas mudanças destrutivas:

- `DROP COLUMN ordem_de_servico.estado_atual`
- `DROP COLUMN os_item_peca.peca_nome`
- `DROP COLUMN os_item_servico.servico_nome`
- `RENAME COLUMN papel.papel -> nome` se isso ainda não tiver sido tratado com compatibilidade
- remoção de triggers, views ou compatibilidades temporárias

### Etapa 2: Ajustar Aplicação e Lambda em Paralelo

Enquanto `V3_expand` está pronta ou já aplicada, preparar os dois consumidores.

#### Aplicação

Deve:

- deixar de ler `estado_atual` diretamente
- derivar o estado pela última linha de `estado_ordem_servico`
- deixar de ler `peca_nome` e `servico_nome`
- buscar nomes via join com `peca` e `servico`
- usar `papel.nome` ou uma camada de compatibilidade temporária

#### Lambda

Deve fazer os mesmos ajustes:

- usar histórico de estado
- não depender das colunas redundantes
- usar `papel.nome`
- escrever mudança de status como evento

### Etapa 3: Deploy em 3 Ondas

#### Onda 1: Banco compatível

Executar apenas a migration `V3_expand`.

Objetivo:

- preparar o banco para ambos os modelos
- não exigir troca simultânea de app e lambda

No pipeline atual:

- rodar migration
- desabilitar seed no rollout, se possível

Sugestao:

```bash
RUN_DB_MIGRATIONS=true
RUN_DB_IMPORT=false
```

#### Onda 2: Publicação dos consumidores

Publicar aplicação e lambda já compatíveis com o modelo expandido.

Objetivo:

- migrar os dois consumidores em paralelo
- reduzir o tempo total de coexistência

Ordem:

- app e lambda podem ser deployados em paralelo
- se não for possível, primeiro o componente com maior volume ou maior criticidade

Durante essa fase, o banco ainda aceita o modelo antigo e o novo.

#### Onda 3: Contração do schema

Depois de confirmar que nenhum consumidor depende mais do modelo antigo, executar `V4_contract`.

Objetivo:

- remover legado
- encerrar a migração

## Como Minimizar o Tempo Total

### 1. Preparar tudo antes da primeira janela

Antes do primeiro deploy, deixar pronto:

- `V3_expand`
- `V4_contract`
- ajustes da aplicação
- ajustes do lambda
- plano de validação

Assim o tempo entre expand e contract fica o menor possível.

### 2. Deployar app e lambda em paralelo

Esse e o maior ganho real de tempo.

Se ambos dependerem de equipes diferentes, alinhar a publicação para a mesma janela.

### 3. Não misturar com mudanças desnecessárias de infra

Se o objetivo é migrar schema, evitar acoplar isso a alterações grandes de Terraform ou rede.

Quanto menos coisa no mesmo deploy, menor o tempo total de execução e diagnóstico.

### 4. Evitar rodar seed na janela de migração

Para esse rollout, o seed só aumenta tempo e ruído.

Usar:

```bash
RUN_DB_IMPORT=false
```

durante a migração principal.

### 5. Usar validação objetiva entre `Expand` e `Contract`

Validar rapidamente:

- queries principais da aplicação
- queries principais do lambda
- leitura de estado derivado
- escrita de novos eventos de estado
- ausência de erro por coluna inexistente

## Compatibilidade Temporária Recomendada

Para reduzir risco entre fases:

- manter `estado_atual` temporariamente
- manter `peca_nome` e `servico_nome` temporariamente
- manter uma estratégia transitória para `papel`

Se necessário, usar:

- `VIEW` para leitura compatível
- trigger temporário para sincronizar histórico e `estado_atual`

Isso reduz a necessidade de corte sincronizado exato.

## Rollback

### Após `V3_expand`

Rollback é simples:

- reverter app
- reverter lambda

O banco continua compatível.

### Após `V4_contract`

Rollback fica mais caro, porque o schema antigo já não existe mais.

Por isso, `V4_contract` só deve acontecer quando:

- app estiver estável
- lambda estiver estável
- logs e métricas confirmarem ausência de dependência antiga

## Execução Recomendada no Pipeline Atual

### Deploy 1

Migration only:

```bash
RUN_DB_MIGRATIONS=true
RUN_DB_IMPORT=false
```

Aplicar apenas `V3_expand`.

### Deploy 2

Deploy da aplicação e do lambda compatíveis com o novo schema.

### Deploy 3

Migration only:

```bash
RUN_DB_MIGRATIONS=true
RUN_DB_IMPORT=false
```

Aplicar `V4_contract`.

## Resumo Executivo

### Melhor caminho

1. quebrar a `V3` atual em `V3_expand` e `V4_contract`
2. aplicar `V3_expand`
3. deployar app e lambda compatíveis em paralelo
4. validar rapidamente
5. aplicar `V4_contract`

### Beneficio

Esse modelo reduz ao máximo:

- tempo total da migração
- necessidade de sincronização rígida entre times
- risco de indisponibilidade por incompatibilidade de schema
