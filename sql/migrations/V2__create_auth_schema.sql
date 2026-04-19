DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'usuario'
      AND column_name IN ('username', 'role')
  ) AND NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'usuario'
      AND column_name = 'pessoa_id'
  ) THEN
    IF to_regclass('public.usuario_legacy') IS NULL THEN
      ALTER TABLE public.usuario RENAME TO usuario_legacy;
    END IF;

    IF to_regclass('public.usuario_seq') IS NOT NULL
      AND to_regclass('public.usuario_legacy_seq') IS NULL THEN
      ALTER SEQUENCE public.usuario_seq RENAME TO usuario_legacy_seq;
    END IF;
  END IF;
END $$;

CREATE SEQUENCE IF NOT EXISTS papel_seq START WITH 1 INCREMENT BY 50;
CREATE SEQUENCE IF NOT EXISTS pessoa_seq START WITH 1 INCREMENT BY 50;
CREATE SEQUENCE IF NOT EXISTS usuario_seq START WITH 1 INCREMENT BY 50;

CREATE TABLE IF NOT EXISTS pessoa (
  id bigint NOT NULL,
  documento varchar(255) NOT NULL,
  CONSTRAINT pessoa_pkey PRIMARY KEY (id),
  CONSTRAINT uk_pessoa_documento UNIQUE (documento)
);

CREATE TABLE IF NOT EXISTS papel (
  id bigint NOT NULL,
  papel varchar(255) NOT NULL,
  CONSTRAINT papel_pkey PRIMARY KEY (id),
  CONSTRAINT uk_papel_papel UNIQUE (papel)
);

CREATE TABLE IF NOT EXISTS usuario (
  id bigint NOT NULL,
  password varchar(255),
  pessoa_id bigint NOT NULL,
  status varchar(255),
  CONSTRAINT auth_usuario_pkey PRIMARY KEY (id),
  CONSTRAINT auth_uk_usuario_pessoa UNIQUE (pessoa_id),
  CONSTRAINT auth_ck_usuario_status CHECK (status IS NULL OR status IN ('ATIVO', 'INATIVO')),
  CONSTRAINT auth_fk_usuario_pessoa
    FOREIGN KEY (pessoa_id)
    REFERENCES pessoa (id)
);

CREATE TABLE IF NOT EXISTS usuario_papel (
  usuario_id bigint NOT NULL,
  papel_id bigint NOT NULL,
  CONSTRAINT usuario_papel_pkey PRIMARY KEY (usuario_id, papel_id),
  CONSTRAINT fk_usuario_papel_usuario
    FOREIGN KEY (usuario_id)
    REFERENCES usuario (id),
  CONSTRAINT fk_usuario_papel_papel
    FOREIGN KEY (papel_id)
    REFERENCES papel (id)
);
