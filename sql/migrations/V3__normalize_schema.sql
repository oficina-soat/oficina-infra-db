DO $$
BEGIN
  IF to_regclass('public.cliente') IS NULL THEN
    RAISE EXCEPTION 'Precondicao falhou: tabela public.cliente nao encontrada.';
  END IF;

  IF to_regclass('public.ordem_de_servico') IS NULL THEN
    RAISE EXCEPTION 'Precondicao falhou: tabela public.ordem_de_servico nao encontrada.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'ordem_de_servico'
      AND column_name = 'estado_atual'
  ) THEN
    RAISE EXCEPTION 'Precondicao falhou: coluna public.ordem_de_servico.estado_atual nao encontrada.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'estado_ordem_servico'
      AND column_name = 'tipo_estado'
  ) THEN
    RAISE EXCEPTION 'Precondicao falhou: coluna public.estado_ordem_servico.tipo_estado nao encontrada.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'estoque_movimento'
      AND column_name = 'ordem_servico_id'
  ) THEN
    RAISE EXCEPTION 'Precondicao falhou: coluna public.estoque_movimento.ordem_servico_id nao encontrada.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'papel'
      AND column_name = 'papel'
  ) THEN
    RAISE EXCEPTION 'Precondicao falhou: coluna public.papel.papel nao encontrada.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'os_item_peca'
      AND column_name = 'peca_nome'
  ) THEN
    RAISE EXCEPTION 'Precondicao falhou: coluna public.os_item_peca.peca_nome nao encontrada.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'os_item_servico'
      AND column_name = 'servico_nome'
  ) THEN
    RAISE EXCEPTION 'Precondicao falhou: coluna public.os_item_servico.servico_nome nao encontrada.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.ordem_de_servico os
    LEFT JOIN public.cliente c ON c.id = os.cliente_id
    WHERE c.id IS NULL
  ) THEN
    RAISE EXCEPTION 'Precondicao falhou: existem ordens de servico com cliente inexistente.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.ordem_de_servico os
    LEFT JOIN public.veiculo v ON v.id = os.veiculo_id
    WHERE v.id IS NULL
  ) THEN
    RAISE EXCEPTION 'Precondicao falhou: existem ordens de servico com veiculo inexistente.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.os_item_peca i
    LEFT JOIN public.peca p ON p.id = i.peca_id
    WHERE p.id IS NULL
  ) THEN
    RAISE EXCEPTION 'Precondicao falhou: existem itens de peca com peca inexistente.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.os_item_servico i
    LEFT JOIN public.servico s ON s.id = i.servico_id
    WHERE s.id IS NULL
  ) THEN
    RAISE EXCEPTION 'Precondicao falhou: existem itens de servico com servico inexistente.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.estoque_saldo es
    LEFT JOIN public.peca p ON p.id = es.peca_id
    WHERE p.id IS NULL
  ) THEN
    RAISE EXCEPTION 'Precondicao falhou: existem saldos de estoque com peca inexistente.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.estoque_movimento em
    LEFT JOIN public.peca p ON p.id = em.peca_id
    WHERE p.id IS NULL
  ) THEN
    RAISE EXCEPTION 'Precondicao falhou: existem movimentos de estoque com peca inexistente.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.estoque_movimento em
    LEFT JOIN public.ordem_de_servico os ON os.id = em.ordem_servico_id
    WHERE em.ordem_servico_id IS NOT NULL
      AND os.id IS NULL
  ) THEN
    RAISE EXCEPTION 'Precondicao falhou: existem movimentos de estoque com ordem de servico inexistente.';
  END IF;

  IF EXISTS (
    SELECT placa
    FROM public.veiculo
    GROUP BY placa
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION 'Precondicao falhou: existem placas duplicadas em public.veiculo.';
  END IF;
END $$;

ALTER TABLE public.cliente
  ALTER COLUMN id SET DEFAULT nextval('public.cliente_seq');
ALTER SEQUENCE public.cliente_seq OWNED BY public.cliente.id;

ALTER TABLE public.estado_ordem_servico
  ALTER COLUMN id SET DEFAULT nextval('public.estado_ordem_servico_seq');
ALTER SEQUENCE public.estado_ordem_servico_seq OWNED BY public.estado_ordem_servico.id;

ALTER TABLE public.estoque_movimento
  ALTER COLUMN id SET DEFAULT nextval('public.estoque_movimento_seq');
ALTER SEQUENCE public.estoque_movimento_seq OWNED BY public.estoque_movimento.id;

ALTER TABLE public.os_item_peca
  ALTER COLUMN id SET DEFAULT nextval('public.os_item_peca_seq');
ALTER SEQUENCE public.os_item_peca_seq OWNED BY public.os_item_peca.id;

ALTER TABLE public.os_item_servico
  ALTER COLUMN id SET DEFAULT nextval('public.os_item_servico_seq');
ALTER SEQUENCE public.os_item_servico_seq OWNED BY public.os_item_servico.id;

ALTER TABLE public.peca
  ALTER COLUMN id SET DEFAULT nextval('public.peca_seq');
ALTER SEQUENCE public.peca_seq OWNED BY public.peca.id;

ALTER TABLE public.servico
  ALTER COLUMN id SET DEFAULT nextval('public.servico_seq');
ALTER SEQUENCE public.servico_seq OWNED BY public.servico.id;

ALTER TABLE public.veiculo
  ALTER COLUMN id SET DEFAULT nextval('public.veiculo_seq');
ALTER SEQUENCE public.veiculo_seq OWNED BY public.veiculo.id;

ALTER TABLE public.papel
  ALTER COLUMN id SET DEFAULT nextval('public.papel_seq');
ALTER SEQUENCE public.papel_seq OWNED BY public.papel.id;

ALTER TABLE public.pessoa
  ALTER COLUMN id SET DEFAULT nextval('public.pessoa_seq');
ALTER SEQUENCE public.pessoa_seq OWNED BY public.pessoa.id;

ALTER TABLE public.usuario
  ALTER COLUMN id SET DEFAULT nextval('public.usuario_seq');
ALTER SEQUENCE public.usuario_seq OWNED BY public.usuario.id;

DO $$
DECLARE
  rec record;
  max_id bigint;
BEGIN
  FOR rec IN
    SELECT *
    FROM (
      VALUES
        ('public.cliente_seq', 'public.cliente', 'id'),
        ('public.estado_ordem_servico_seq', 'public.estado_ordem_servico', 'id'),
        ('public.estoque_movimento_seq', 'public.estoque_movimento', 'id'),
        ('public.os_item_peca_seq', 'public.os_item_peca', 'id'),
        ('public.os_item_servico_seq', 'public.os_item_servico', 'id'),
        ('public.peca_seq', 'public.peca', 'id'),
        ('public.servico_seq', 'public.servico', 'id'),
        ('public.veiculo_seq', 'public.veiculo', 'id'),
        ('public.papel_seq', 'public.papel', 'id'),
        ('public.pessoa_seq', 'public.pessoa', 'id'),
        ('public.usuario_seq', 'public.usuario', 'id')
    ) AS sequences(seq_name, table_name, column_name)
  LOOP
    EXECUTE format('SELECT max(%I) FROM %s', rec.column_name, rec.table_name) INTO max_id;

    IF max_id IS NULL THEN
      EXECUTE format('SELECT setval(%L, 1, false)', rec.seq_name);
    ELSE
      EXECUTE format('SELECT setval(%L, %s, true)', rec.seq_name, max_id);
    END IF;
  END LOOP;
END $$;

CREATE TABLE public.dominio_estado_ordem_servico (
  codigo varchar(30) NOT NULL,
  descricao varchar(255) NOT NULL,
  ordem smallint NOT NULL,
  estado_final boolean NOT NULL DEFAULT false,
  CONSTRAINT dominio_estado_ordem_servico_pkey PRIMARY KEY (codigo),
  CONSTRAINT uk_dominio_estado_ordem_servico_ordem UNIQUE (ordem)
);

INSERT INTO public.dominio_estado_ordem_servico (codigo, descricao, ordem, estado_final) VALUES
  ('RECEBIDA', 'Recebida', 1, false),
  ('EM_DIAGNOSTICO', 'Em diagnostico', 2, false),
  ('AGUARDANDO_APROVACAO', 'Aguardando aprovacao', 3, false),
  ('EM_EXECUCAO', 'Em execucao', 4, false),
  ('FINALIZADA', 'Finalizada', 5, true),
  ('ENTREGUE', 'Entregue', 6, true);

CREATE TABLE public.dominio_tipo_movimento_estoque (
  codigo varchar(20) NOT NULL,
  descricao varchar(255) NOT NULL,
  CONSTRAINT dominio_tipo_movimento_estoque_pkey PRIMARY KEY (codigo)
);

INSERT INTO public.dominio_tipo_movimento_estoque (codigo, descricao) VALUES
  ('ENTRADA', 'Entrada'),
  ('SAIDA', 'Saida'),
  ('AJUSTE', 'Ajuste');

CREATE TABLE public.dominio_status_usuario (
  codigo varchar(20) NOT NULL,
  descricao varchar(255) NOT NULL,
  CONSTRAINT dominio_status_usuario_pkey PRIMARY KEY (codigo)
);

INSERT INTO public.dominio_status_usuario (codigo, descricao) VALUES
  ('ATIVO', 'Ativo'),
  ('INATIVO', 'Inativo');

ALTER TABLE public.estado_ordem_servico
  ALTER COLUMN tipo_estado TYPE varchar(30);

ALTER TABLE public.papel
  RENAME COLUMN papel TO nome;

ALTER TABLE public.estoque_movimento
  RENAME COLUMN ordem_servico_id TO ordem_de_servico_id;

ALTER TABLE public.papel
  RENAME CONSTRAINT uk_papel_papel TO uk_papel_nome;

ALTER TABLE public.usuario
  RENAME CONSTRAINT auth_usuario_pkey TO usuario_pkey;

ALTER TABLE public.usuario
  RENAME CONSTRAINT auth_uk_usuario_pessoa TO uk_usuario_pessoa;

ALTER TABLE public.usuario
  RENAME CONSTRAINT auth_ck_usuario_status TO ck_usuario_status;

ALTER TABLE public.usuario
  RENAME CONSTRAINT auth_fk_usuario_pessoa TO fk_usuario_pessoa;

UPDATE public.usuario
SET status = 'ATIVO'
WHERE status IS NULL;

INSERT INTO public.estado_ordem_servico (id, data_estado, tipo_estado, ordem_de_servico_id)
SELECT nextval('public.estado_ordem_servico_seq'),
       GREATEST(os.atualizado_em, os.criado_em, ultimo_evento.data_estado),
       os.estado_atual,
       os.id
FROM public.ordem_de_servico os
LEFT JOIN LATERAL (
  SELECT eos.tipo_estado, eos.data_estado
  FROM public.estado_ordem_servico eos
  WHERE eos.ordem_de_servico_id = os.id
  ORDER BY eos.data_estado DESC, eos.id DESC
  LIMIT 1
) ultimo_evento ON true
WHERE ultimo_evento.tipo_estado IS DISTINCT FROM os.estado_atual;

ALTER TABLE public.ordem_de_servico
  ADD CONSTRAINT fk_ordem_de_servico_cliente
    FOREIGN KEY (cliente_id)
    REFERENCES public.cliente (id),
  ADD CONSTRAINT fk_ordem_de_servico_veiculo
    FOREIGN KEY (veiculo_id)
    REFERENCES public.veiculo (id);

ALTER TABLE public.estado_ordem_servico
  ADD CONSTRAINT fk_estado_ordem_servico_tipo_estado
    FOREIGN KEY (tipo_estado)
    REFERENCES public.dominio_estado_ordem_servico (codigo);

ALTER TABLE public.os_item_peca
  ADD CONSTRAINT fk_os_item_peca_peca
    FOREIGN KEY (peca_id)
    REFERENCES public.peca (id);

ALTER TABLE public.os_item_servico
  ADD CONSTRAINT fk_os_item_servico_servico
    FOREIGN KEY (servico_id)
    REFERENCES public.servico (id);

ALTER TABLE public.estoque_saldo
  ADD CONSTRAINT fk_estoque_saldo_peca
    FOREIGN KEY (peca_id)
    REFERENCES public.peca (id);

ALTER TABLE public.estoque_movimento
  ADD CONSTRAINT fk_estoque_movimento_peca
    FOREIGN KEY (peca_id)
    REFERENCES public.peca (id),
  ADD CONSTRAINT fk_estoque_movimento_ordem_de_servico
    FOREIGN KEY (ordem_de_servico_id)
    REFERENCES public.ordem_de_servico (id);

ALTER TABLE public.usuario
  ALTER COLUMN status SET NOT NULL,
  ALTER COLUMN status SET DEFAULT 'ATIVO';

ALTER TABLE public.usuario
  ADD CONSTRAINT fk_usuario_status
    FOREIGN KEY (status)
    REFERENCES public.dominio_status_usuario (codigo);

ALTER TABLE public.estoque_movimento
  ADD CONSTRAINT fk_estoque_movimento_tipo
    FOREIGN KEY (tipo)
    REFERENCES public.dominio_tipo_movimento_estoque (codigo);

ALTER TABLE public.veiculo
  ADD CONSTRAINT uk_veiculo_placa UNIQUE (placa);

ALTER TABLE public.os_item_peca
  ADD CONSTRAINT ck_os_item_peca_quantidade_positiva CHECK (quantidade > 0),
  ADD CONSTRAINT ck_os_item_peca_valor_unitario_nao_negativo CHECK (valor_unitario >= 0),
  ADD CONSTRAINT ck_os_item_peca_valor_total_nao_negativo CHECK (valor_total >= 0);

ALTER TABLE public.os_item_servico
  ADD CONSTRAINT ck_os_item_servico_quantidade_positiva CHECK (quantidade > 0),
  ADD CONSTRAINT ck_os_item_servico_valor_unitario_nao_negativo CHECK (valor_unitario >= 0),
  ADD CONSTRAINT ck_os_item_servico_valor_total_nao_negativo CHECK (valor_total >= 0);

ALTER TABLE public.estoque_saldo
  ADD CONSTRAINT ck_estoque_saldo_quantidade_nao_negativa CHECK (quantidade >= 0);

ALTER TABLE public.estoque_movimento
  ADD CONSTRAINT ck_estoque_movimento_quantidade_positiva CHECK (quantidade > 0);

CREATE INDEX ix_ordem_de_servico_cliente ON public.ordem_de_servico (cliente_id);
CREATE INDEX ix_ordem_de_servico_veiculo ON public.ordem_de_servico (veiculo_id);
CREATE INDEX ix_estado_ordem_servico_os_data ON public.estado_ordem_servico (ordem_de_servico_id, data_estado DESC, id DESC);
CREATE INDEX ix_estoque_movimento_peca ON public.estoque_movimento (peca_id);
CREATE INDEX ix_estoque_movimento_os ON public.estoque_movimento (ordem_de_servico_id);
CREATE INDEX ix_usuario_papel_papel_id ON public.usuario_papel (papel_id);

ALTER TABLE public.estado_ordem_servico
  DROP CONSTRAINT ck_estado_ordem_servico_tipo_estado;

ALTER TABLE public.estoque_movimento
  DROP CONSTRAINT ck_estoque_movimento_tipo;

ALTER TABLE public.usuario
  DROP CONSTRAINT ck_usuario_status;

ALTER TABLE public.os_item_peca
  DROP COLUMN peca_nome;

ALTER TABLE public.os_item_servico
  DROP COLUMN servico_nome;

ALTER TABLE public.ordem_de_servico
  DROP COLUMN estado_atual;
