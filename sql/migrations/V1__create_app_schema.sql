CREATE SEQUENCE cliente_seq START WITH 1 INCREMENT BY 50;
CREATE SEQUENCE estado_ordem_servico_seq START WITH 1 INCREMENT BY 50;
CREATE SEQUENCE estoque_movimento_seq START WITH 1 INCREMENT BY 50;
CREATE SEQUENCE os_item_peca_seq START WITH 1 INCREMENT BY 50;
CREATE SEQUENCE os_item_servico_seq START WITH 1 INCREMENT BY 50;
CREATE SEQUENCE peca_seq START WITH 1 INCREMENT BY 50;
CREATE SEQUENCE servico_seq START WITH 1 INCREMENT BY 50;
CREATE SEQUENCE veiculo_seq START WITH 1 INCREMENT BY 50;

CREATE TABLE cliente (
  id bigint NOT NULL,
  documento varchar(255) NOT NULL,
  email varchar(255) NOT NULL,
  CONSTRAINT cliente_pkey PRIMARY KEY (id),
  CONSTRAINT uk_cliente_documento UNIQUE (documento),
  CONSTRAINT uk_cliente_email UNIQUE (email)
);

CREATE TABLE veiculo (
  id bigint NOT NULL,
  ano integer NOT NULL,
  marca varchar(255) NOT NULL,
  modelo varchar(255) NOT NULL,
  placa varchar(255) NOT NULL,
  CONSTRAINT veiculo_pkey PRIMARY KEY (id)
);

CREATE TABLE ordem_de_servico (
  id uuid NOT NULL,
  atualizado_em timestamp(6) with time zone NOT NULL,
  cliente_id bigint NOT NULL,
  criado_em timestamp(6) with time zone NOT NULL,
  estado_atual varchar(30) NOT NULL,
  veiculo_id bigint NOT NULL,
  CONSTRAINT ordem_de_servico_pkey PRIMARY KEY (id),
  CONSTRAINT ck_ordem_de_servico_estado_atual CHECK (
    estado_atual IN (
      'RECEBIDA',
      'EM_DIAGNOSTICO',
      'AGUARDANDO_APROVACAO',
      'EM_EXECUCAO',
      'FINALIZADA',
      'ENTREGUE'
    )
  )
);

CREATE TABLE estado_ordem_servico (
  id bigint NOT NULL,
  data_estado timestamp(6) with time zone NOT NULL,
  tipo_estado varchar(20) NOT NULL,
  ordem_de_servico_id uuid NOT NULL,
  CONSTRAINT estado_ordem_servico_pkey PRIMARY KEY (id),
  CONSTRAINT ck_estado_ordem_servico_tipo_estado CHECK (
    tipo_estado IN (
      'RECEBIDA',
      'EM_DIAGNOSTICO',
      'AGUARDANDO_APROVACAO',
      'EM_EXECUCAO',
      'FINALIZADA',
      'ENTREGUE'
    )
  ),
  CONSTRAINT fk_estado_ordem_servico_os
    FOREIGN KEY (ordem_de_servico_id)
    REFERENCES ordem_de_servico (id)
);

CREATE TABLE os_item_peca (
  id bigint NOT NULL,
  ordem_de_servico_id uuid NOT NULL,
  peca_id bigint NOT NULL,
  peca_nome varchar(255) NOT NULL,
  quantidade numeric(15, 3) NOT NULL,
  valor_total numeric(14, 2) NOT NULL,
  valor_unitario numeric(14, 2) NOT NULL,
  CONSTRAINT os_item_peca_pkey PRIMARY KEY (id),
  CONSTRAINT fk_os_item_peca_os
    FOREIGN KEY (ordem_de_servico_id)
    REFERENCES ordem_de_servico (id)
);

CREATE INDEX ix_os_item_peca_os ON os_item_peca (ordem_de_servico_id);
CREATE INDEX ix_os_item_peca_peca ON os_item_peca (peca_id);

CREATE TABLE os_item_servico (
  id bigint NOT NULL,
  ordem_de_servico_id uuid NOT NULL,
  quantidade numeric(15, 3) NOT NULL,
  servico_id bigint NOT NULL,
  servico_nome varchar(255) NOT NULL,
  valor_total numeric(14, 2) NOT NULL,
  valor_unitario numeric(14, 2) NOT NULL,
  CONSTRAINT os_item_servico_pkey PRIMARY KEY (id),
  CONSTRAINT fk_os_item_servico_os
    FOREIGN KEY (ordem_de_servico_id)
    REFERENCES ordem_de_servico (id)
);

CREATE INDEX ix_os_item_servico_os ON os_item_servico (ordem_de_servico_id);
CREATE INDEX ix_os_item_servico_servico ON os_item_servico (servico_id);

CREATE TABLE peca (
  id bigint NOT NULL,
  nome varchar(255) NOT NULL,
  CONSTRAINT peca_pkey PRIMARY KEY (id)
);

CREATE TABLE servico (
  id bigint NOT NULL,
  nome varchar(255) NOT NULL,
  CONSTRAINT servico_pkey PRIMARY KEY (id)
);

CREATE TABLE estoque_saldo (
  peca_id bigint NOT NULL,
  quantidade numeric(15, 3) NOT NULL,
  CONSTRAINT estoque_saldo_pkey PRIMARY KEY (peca_id)
);

CREATE TABLE estoque_movimento (
  id bigint NOT NULL,
  data_movimento timestamp(6) with time zone NOT NULL,
  observacao varchar(255),
  ordem_servico_id uuid,
  peca_id bigint NOT NULL,
  quantidade numeric(15, 3) NOT NULL,
  tipo varchar(20) NOT NULL,
  CONSTRAINT estoque_movimento_pkey PRIMARY KEY (id),
  CONSTRAINT ck_estoque_movimento_tipo CHECK (tipo IN ('ENTRADA', 'SAIDA', 'AJUSTE'))
);
