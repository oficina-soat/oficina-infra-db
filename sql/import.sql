-- noinspection SqlResolve
INSERT INTO public.pessoa (documento, tipo_pessoa, nome, email) VALUES
    ('84191404067', 'FISICA', 'Administrador Laboratorio', 'admin@oficina.com'),
    ('36655462007', 'FISICA', 'Mecanico Laboratorio', 'mecanico@oficina.com'),
    ('17245011010', 'FISICA', 'Recepcionista Laboratorio', 'recepcao@oficina.com'),
    ('50132372037', 'FISICA', 'Cliente Laboratorio 1', 'cliente1@oficina.com'),
    ('12345678900', 'FISICA', 'Cliente Laboratorio 2', 'cliente2@oficina.com')
ON CONFLICT (documento) DO UPDATE SET
    tipo_pessoa = EXCLUDED.tipo_pessoa,
    nome = EXCLUDED.nome,
    email = EXCLUDED.email;
SELECT setval('pessoa_seq', GREATEST((SELECT COALESCE(MAX(id), 0) FROM public.pessoa), 1), true);

INSERT INTO public.papel (nome) VALUES
    ('administrativo'),
    ('mecanico'),
    ('recepcionista')
ON CONFLICT (nome) DO UPDATE SET
    nome = EXCLUDED.nome;
SELECT setval('papel_seq', GREATEST((SELECT COALESCE(MAX(id), 0) FROM public.papel), 1), true);

-- noinspection SqlResolve
INSERT INTO public.usuario (pessoa_id, password, status)
SELECT p.id,
       seed.password,
       seed.status
FROM (
    VALUES
        ('84191404067', '$2a$10$OqdJA0ubv0ANPU4TfphJAOeZ0QcQca3GlnLtuahh6C6bV5how5gbm', 'ATIVO'),
        ('36655462007', '$2a$10$OqdJA0ubv0ANPU4TfphJAOeZ0QcQca3GlnLtuahh6C6bV5how5gbm', 'ATIVO'),
        ('17245011010', '$2a$10$OqdJA0ubv0ANPU4TfphJAOeZ0QcQca3GlnLtuahh6C6bV5how5gbm', 'ATIVO')
) AS seed(documento, password, status)
JOIN public.pessoa p
  ON p.documento = seed.documento
ON CONFLICT (pessoa_id) DO UPDATE SET
    password = EXCLUDED.password,
    status = EXCLUDED.status;
SELECT setval('usuario_seq', GREATEST((SELECT COALESCE(MAX(id), 0) FROM public.usuario), 1), true);

INSERT INTO public.usuario_papel (usuario_id, papel_id)
SELECT u.id,
       p.id
FROM (
    VALUES
        ('84191404067', 'administrativo'),
        ('84191404067', 'mecanico'),
        ('84191404067', 'recepcionista'),
        ('36655462007', 'mecanico'),
        ('17245011010', 'recepcionista')
) AS seed(documento, papel_nome)
JOIN public.pessoa pessoa
  ON pessoa.documento = seed.documento
JOIN public.usuario u
  ON u.pessoa_id = pessoa.id
JOIN public.papel p
  ON p.nome = seed.papel_nome
ON CONFLICT (usuario_id, papel_id) DO NOTHING;

-- noinspection SqlResolve
INSERT INTO public.cliente (pessoa_id, documento, email)
SELECT p.id,
       seed.documento,
       seed.email
FROM (
    VALUES
        ('50132372037', 'cliente1@oficina.com'),
        ('12345678900', 'cliente2@oficina.com')
) AS seed(documento, email)
JOIN public.pessoa p
  ON p.documento = seed.documento
ON CONFLICT (documento) DO UPDATE SET
    pessoa_id = EXCLUDED.pessoa_id,
    email = EXCLUDED.email;
SELECT setval('cliente_seq', GREATEST((SELECT COALESCE(MAX(id), 0) FROM public.cliente), 1), true);

INSERT INTO public.veiculo (placa, marca, modelo, ano) VALUES
    ('ABC1234', '11111111111', '11111111111', 11111111),
    ('ABC1D23', '11111111111', '11111111111', 11111111)
ON CONFLICT (placa) DO UPDATE SET
    marca = EXCLUDED.marca,
    modelo = EXCLUDED.modelo,
    ano = EXCLUDED.ano;
SELECT setval('veiculo_seq', GREATEST((SELECT COALESCE(MAX(id), 0) FROM public.veiculo), 1), true);

INSERT INTO public.ordem_de_servico (id, cliente_id, veiculo_id, criado_em, atualizado_em)
SELECT seed.id,
       c.id,
       v.id,
       seed.criado_em,
       seed.atualizado_em
FROM (
    VALUES
        ('2b2276e8-fa72-4f4c-a3b0-2c5b1bf427ef'::uuid, '50132372037', 'ABC1234', '2025-12-14 17:28:14.046297 +00:00'::timestamptz, '2025-12-14 17:28:14.046297 +00:00'::timestamptz),
        ('1b2276e8-fa72-4f4c-a3b0-2c5b1bf427ef'::uuid, '50132372037', 'ABC1234', '2025-10-14 17:20:14.046297 +00:00'::timestamptz, '2025-12-14 17:20:14.046297 +00:00'::timestamptz),
        ('f05dd17b-daae-4658-af7c-363dd6e6fdfb'::uuid, '50132372037', 'ABC1234', '2025-12-14 17:28:14.714212 +00:00'::timestamptz, '2025-12-14 17:28:14.714212 +00:00'::timestamptz),
        ('5b2276e8-fa72-4f4c-a3b0-2c5b1bf427ef'::uuid, '50132372037', 'ABC1234', '2024-12-14 17:28:14.714212 +00:00'::timestamptz, '2025-12-14 17:28:14.714212 +00:00'::timestamptz),
        ('4b2276e8-fa72-4f4c-a3b0-2c5b1bf427ef'::uuid, '50132372037', 'ABC1234', '2025-12-14 17:28:14.714212 +00:00'::timestamptz, '2025-12-14 17:28:14.714212 +00:00'::timestamptz),
        ('6b2276e8-fa72-4f4c-a3b0-2c5b1bf427ef'::uuid, '50132372037', 'ABC1234', '2025-12-14 17:28:14.714212 +00:00'::timestamptz, '2025-12-14 17:28:14.714212 +00:00'::timestamptz),
        ('7b2276e8-fa72-4f4c-a3b0-2c5b1bf427ef'::uuid, '50132372037', 'ABC1234', '2025-12-14 17:28:14.714212 +00:00'::timestamptz, '2025-12-14 17:28:14.714212 +00:00'::timestamptz),
        ('4298695b-d6ae-45ac-a659-c4de90f81eb4'::uuid, '12345678900', 'ABC1D23', '2026-01-17 10:00:00.000000 +00:00'::timestamptz, '2026-01-17 10:00:00.000000 +00:00'::timestamptz)
) AS seed(id, cliente_documento, veiculo_placa, criado_em, atualizado_em)
JOIN public.cliente c
  ON c.documento = seed.cliente_documento
JOIN public.veiculo v
  ON v.placa = seed.veiculo_placa
ON CONFLICT (id) DO UPDATE SET
    cliente_id = EXCLUDED.cliente_id,
    veiculo_id = EXCLUDED.veiculo_id,
    criado_em = EXCLUDED.criado_em,
    atualizado_em = EXCLUDED.atualizado_em;

INSERT INTO public.estado_ordem_servico (id, ordem_de_servico_id, tipo_estado, data_estado)
SELECT nextval('public.estado_ordem_servico_seq'),
       seed.ordem_de_servico_id,
       seed.tipo_estado,
       seed.data_estado
FROM (
    VALUES
        ('2b2276e8-fa72-4f4c-a3b0-2c5b1bf427ef'::uuid, 'EM_DIAGNOSTICO'::varchar(30), '2025-12-14 17:28:14.046297 +00:00'::timestamptz),
        ('1b2276e8-fa72-4f4c-a3b0-2c5b1bf427ef'::uuid, 'EM_DIAGNOSTICO'::varchar(30), '2025-12-14 17:20:14.046297 +00:00'::timestamptz),
        ('f05dd17b-daae-4658-af7c-363dd6e6fdfb'::uuid, 'RECEBIDA'::varchar(30), '2025-12-14 17:28:14.714212 +00:00'::timestamptz),
        ('5b2276e8-fa72-4f4c-a3b0-2c5b1bf427ef'::uuid, 'AGUARDANDO_APROVACAO'::varchar(30), '2025-12-14 17:28:14.714212 +00:00'::timestamptz),
        ('4b2276e8-fa72-4f4c-a3b0-2c5b1bf427ef'::uuid, 'AGUARDANDO_APROVACAO'::varchar(30), '2025-12-14 17:28:14.714212 +00:00'::timestamptz),
        ('6b2276e8-fa72-4f4c-a3b0-2c5b1bf427ef'::uuid, 'EM_EXECUCAO'::varchar(30), '2025-12-14 17:28:14.714212 +00:00'::timestamptz),
        ('7b2276e8-fa72-4f4c-a3b0-2c5b1bf427ef'::uuid, 'FINALIZADA'::varchar(30), '2025-12-14 17:28:14.714212 +00:00'::timestamptz),
        ('4298695b-d6ae-45ac-a659-c4de90f81eb4'::uuid, 'RECEBIDA'::varchar(30), '2026-01-17 10:00:00.000000 +00:00'::timestamptz)
) AS seed(ordem_de_servico_id, tipo_estado, data_estado)
WHERE NOT EXISTS (
    SELECT 1
    FROM public.estado_ordem_servico eos
    WHERE eos.ordem_de_servico_id = seed.ordem_de_servico_id
      AND eos.tipo_estado = seed.tipo_estado
      AND eos.data_estado = seed.data_estado
);
SELECT setval('estado_ordem_servico_seq', GREATEST((SELECT COALESCE(MAX(id), 0) FROM public.estado_ordem_servico), 1), true);

INSERT INTO public.peca (id, nome) VALUES
    (1, 'Volante'),
    (2, 'Pneu'),
    (3, 'Tapete')
ON CONFLICT (id) DO UPDATE SET
    nome = EXCLUDED.nome;
SELECT setval('peca_seq', GREATEST((SELECT COALESCE(MAX(id), 0) FROM public.peca), 1), true);

INSERT INTO public.os_item_peca (quantidade, valor_total, valor_unitario, id, peca_id, ordem_de_servico_id) VALUES
    (2.000, 2.00, 1.00, 1, 1, '2b2276e8-fa72-4f4c-a3b0-2c5b1bf427ef'),
    (2.000, 100.00, 50.00, 2, 1, '4298695b-d6ae-45ac-a659-c4de90f81eb4')
ON CONFLICT (id) DO UPDATE SET
    quantidade = EXCLUDED.quantidade,
    valor_total = EXCLUDED.valor_total,
    valor_unitario = EXCLUDED.valor_unitario,
    peca_id = EXCLUDED.peca_id,
    ordem_de_servico_id = EXCLUDED.ordem_de_servico_id;
SELECT setval('os_item_peca_seq', GREATEST((SELECT COALESCE(MAX(id), 0) FROM public.os_item_peca), 1), true);

INSERT INTO public.estoque_saldo (quantidade, peca_id) VALUES
    (50.000, 1)
ON CONFLICT (peca_id) DO UPDATE SET
    quantidade = EXCLUDED.quantidade;

INSERT INTO public.servico (id, nome) VALUES
    (1, 'Troca de oleo')
ON CONFLICT (id) DO UPDATE SET
    nome = EXCLUDED.nome;
SELECT setval('servico_seq', GREATEST((SELECT COALESCE(MAX(id), 0) FROM public.servico), 1), true);

INSERT INTO public.os_item_servico (quantidade, valor_total, valor_unitario, id, servico_id, ordem_de_servico_id) VALUES
    (1.000, 120.00, 150.00, 1, 1, '4298695b-d6ae-45ac-a659-c4de90f81eb4')
ON CONFLICT (id) DO UPDATE SET
    quantidade = EXCLUDED.quantidade,
    valor_total = EXCLUDED.valor_total,
    valor_unitario = EXCLUDED.valor_unitario,
    servico_id = EXCLUDED.servico_id,
    ordem_de_servico_id = EXCLUDED.ordem_de_servico_id;
SELECT setval('os_item_servico_seq', GREATEST((SELECT COALESCE(MAX(id), 0) FROM public.os_item_servico), 1), true);
