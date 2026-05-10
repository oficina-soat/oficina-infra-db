DO $$
BEGIN
  IF to_regclass('public.pessoa') IS NULL THEN
    RAISE EXCEPTION 'Precondicao falhou: tabela public.pessoa nao encontrada.';
  END IF;

  IF to_regclass('public.cliente') IS NULL THEN
    RAISE EXCEPTION 'Precondicao falhou: tabela public.cliente nao encontrada.';
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_cliente_sync_pessoa ON public.cliente;
DROP FUNCTION IF EXISTS public.fn_sync_cliente_pessoa();

ALTER TABLE public.cliente
  DROP CONSTRAINT IF EXISTS uk_cliente_documento;

ALTER TABLE public.cliente
  DROP COLUMN IF EXISTS documento;

ALTER TABLE public.pessoa
  DROP COLUMN IF EXISTS email;
