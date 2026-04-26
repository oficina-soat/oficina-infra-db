DO $$
BEGIN
  IF to_regclass('public.pessoa') IS NULL THEN
    RAISE EXCEPTION 'Precondicao falhou: tabela public.pessoa nao encontrada.';
  END IF;

  IF to_regclass('public.cliente') IS NULL THEN
    RAISE EXCEPTION 'Precondicao falhou: tabela public.cliente nao encontrada.';
  END IF;

  IF to_regclass('public.usuario') IS NULL THEN
    RAISE EXCEPTION 'Precondicao falhou: tabela public.usuario nao encontrada.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'cliente'
      AND column_name = 'documento'
  ) THEN
    RAISE EXCEPTION 'Precondicao falhou: coluna public.cliente.documento nao encontrada.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'cliente'
      AND column_name = 'email'
  ) THEN
    RAISE EXCEPTION 'Precondicao falhou: coluna public.cliente.email nao encontrada.';
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.dominio_tipo_pessoa (
  codigo varchar(20) NOT NULL,
  descricao varchar(255) NOT NULL,
  CONSTRAINT dominio_tipo_pessoa_pkey PRIMARY KEY (codigo)
);

INSERT INTO public.dominio_tipo_pessoa (codigo, descricao) VALUES
  ('FISICA', 'Pessoa fisica'),
  ('JURIDICA', 'Pessoa juridica')
ON CONFLICT (codigo) DO UPDATE SET
  descricao = EXCLUDED.descricao;

ALTER TABLE public.pessoa
  ADD COLUMN IF NOT EXISTS tipo_pessoa varchar(20),
  ADD COLUMN IF NOT EXISTS nome varchar(255),
  ADD COLUMN IF NOT EXISTS email varchar(255);

ALTER TABLE public.cliente
  ADD COLUMN IF NOT EXISTS pessoa_id bigint;

CREATE OR REPLACE FUNCTION public.fn_derivar_tipo_pessoa(documento_input varchar)
RETURNS varchar
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  documento_numerico varchar;
BEGIN
  documento_numerico := regexp_replace(coalesce(documento_input, ''), '\D', '', 'g');

  CASE length(documento_numerico)
    WHEN 11 THEN RETURN 'FISICA';
    WHEN 14 THEN RETURN 'JURIDICA';
    ELSE
      RAISE EXCEPTION 'Documento invalido para derivar tipo de pessoa: %', documento_input;
  END CASE;
END;
$$;

UPDATE public.pessoa
SET tipo_pessoa = public.fn_derivar_tipo_pessoa(documento)
WHERE tipo_pessoa IS NULL;

INSERT INTO public.pessoa (id, documento, tipo_pessoa, email)
SELECT nextval('public.pessoa_seq'),
       c.documento,
       public.fn_derivar_tipo_pessoa(c.documento),
       c.email
FROM public.cliente c
LEFT JOIN public.pessoa p
  ON p.documento = c.documento
WHERE p.id IS NULL;

UPDATE public.pessoa p
SET email = c.email
FROM public.cliente c
WHERE c.documento = p.documento
  AND (p.email IS NULL OR p.email = '');

UPDATE public.cliente c
SET pessoa_id = p.id
FROM public.pessoa p
WHERE p.documento = c.documento
  AND (c.pessoa_id IS NULL OR c.pessoa_id <> p.id);

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.cliente
    WHERE pessoa_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Migracao falhou: existem clientes sem pessoa vinculada.';
  END IF;
END $$;

ALTER TABLE public.pessoa
  ALTER COLUMN tipo_pessoa SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'fk_pessoa_tipo_pessoa'
      AND conrelid = 'public.pessoa'::regclass
  ) THEN
    ALTER TABLE public.pessoa
      ADD CONSTRAINT fk_pessoa_tipo_pessoa
        FOREIGN KEY (tipo_pessoa)
        REFERENCES public.dominio_tipo_pessoa (codigo);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'uk_cliente_pessoa'
      AND conrelid = 'public.cliente'::regclass
  ) THEN
    ALTER TABLE public.cliente
      ADD CONSTRAINT uk_cliente_pessoa UNIQUE (pessoa_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'fk_cliente_pessoa'
      AND conrelid = 'public.cliente'::regclass
  ) THEN
    ALTER TABLE public.cliente
      ADD CONSTRAINT fk_cliente_pessoa
        FOREIGN KEY (pessoa_id)
        REFERENCES public.pessoa (id);
  END IF;
END $$;

ALTER TABLE public.cliente
  ALTER COLUMN pessoa_id SET NOT NULL;

CREATE INDEX IF NOT EXISTS ix_cliente_pessoa ON public.cliente (pessoa_id);

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.usuario u
    JOIN public.pessoa p ON p.id = u.pessoa_id
    WHERE public.fn_derivar_tipo_pessoa(p.documento) <> 'FISICA'
  ) THEN
    RAISE EXCEPTION 'Migracao falhou: existem usuarios vinculados a pessoas nao fisicas.';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.fn_sync_cliente_pessoa()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  pessoa_encontrada_id bigint;
  tipo_pessoa_calculado varchar(20);
BEGIN
  IF pg_trigger_depth() > 1 THEN
    RETURN NEW;
  END IF;

  tipo_pessoa_calculado := public.fn_derivar_tipo_pessoa(NEW.documento);

  IF NEW.pessoa_id IS NOT NULL THEN
    SELECT p.id
    INTO pessoa_encontrada_id
    FROM public.pessoa p
    WHERE p.documento = NEW.documento
    FOR UPDATE;

    IF pessoa_encontrada_id IS NOT NULL AND pessoa_encontrada_id <> NEW.pessoa_id THEN
      UPDATE public.pessoa
      SET tipo_pessoa = tipo_pessoa_calculado,
          email = NEW.email
      WHERE id = pessoa_encontrada_id;

      NEW.pessoa_id := pessoa_encontrada_id;
      RETURN NEW;
    END IF;

    PERFORM 1
    FROM public.pessoa
    WHERE id = NEW.pessoa_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Pessoa % informada para cliente nao existe.', NEW.pessoa_id;
    END IF;

    UPDATE public.pessoa
    SET documento = NEW.documento,
        tipo_pessoa = tipo_pessoa_calculado,
        email = NEW.email
    WHERE id = NEW.pessoa_id;

    RETURN NEW;
  END IF;

  SELECT p.id
  INTO pessoa_encontrada_id
  FROM public.pessoa p
  WHERE p.documento = NEW.documento
  FOR UPDATE;

  IF pessoa_encontrada_id IS NULL THEN
    INSERT INTO public.pessoa (id, documento, tipo_pessoa, email)
    VALUES (nextval('public.pessoa_seq'), NEW.documento, tipo_pessoa_calculado, NEW.email)
    RETURNING id INTO pessoa_encontrada_id;
  ELSE
    UPDATE public.pessoa
    SET tipo_pessoa = tipo_pessoa_calculado,
        email = NEW.email
    WHERE id = pessoa_encontrada_id;
  END IF;

  NEW.pessoa_id := pessoa_encontrada_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cliente_sync_pessoa ON public.cliente;

CREATE TRIGGER trg_cliente_sync_pessoa
BEFORE INSERT OR UPDATE OF documento, email, pessoa_id
ON public.cliente
FOR EACH ROW
EXECUTE FUNCTION public.fn_sync_cliente_pessoa();
