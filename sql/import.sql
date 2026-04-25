INSERT INTO public.pessoa (id, documento) VALUES
    (1, '84191404067'),
    (2, '36655462007'),
    (3, '17245011010')
ON CONFLICT (id) DO UPDATE SET
    documento = EXCLUDED.documento;
SELECT setval('pessoa_seq', GREATEST((SELECT COALESCE(MAX(id), 0) FROM public.pessoa), 1), true);

INSERT INTO public.papel (id, nome) VALUES
    (1, 'administrativo'),
    (2, 'mecanico'),
    (3, 'recepcionista')
ON CONFLICT (id) DO UPDATE SET
    nome = EXCLUDED.nome;
SELECT setval('papel_seq', GREATEST((SELECT COALESCE(MAX(id), 0) FROM public.papel), 1), true);

INSERT INTO public.usuario (id, pessoa_id, password, status) VALUES
    (1, 1, '$2a$12$1CBAHD.wKOCpNFGnEMUfn.sMSf8Muag0NWrtrBBxJpssTdZ1OCN3e', 'ATIVO'),
    (2, 2, '$2a$12$1CBAHD.wKOCpNFGnEMUfn.sMSf8Muag0NWrtrBBxJpssTdZ1OCN3e', 'ATIVO'),
    (3, 3, '$2a$12$1CBAHD.wKOCpNFGnEMUfn.sMSf8Muag0NWrtrBBxJpssTdZ1OCN3e', 'ATIVO')
ON CONFLICT (id) DO UPDATE SET
    pessoa_id = EXCLUDED.pessoa_id,
    password = EXCLUDED.password,
    status = EXCLUDED.status;
SELECT setval('usuario_seq', GREATEST((SELECT COALESCE(MAX(id), 0) FROM public.usuario), 1), true);

INSERT INTO public.usuario_papel (usuario_id, papel_id) VALUES
    (1, 1),
    (1, 2),
    (1, 3),
    (2, 2),
    (3, 3)
ON CONFLICT (usuario_id, papel_id) DO NOTHING;

INSERT INTO public.cliente (id, documento, email) VALUES
    (1, '50132372037', 'cliente1@oficina.com'),
    (2, '12345678900', 'cliente2@oficina.com')
ON CONFLICT (id) DO UPDATE SET
    documento = EXCLUDED.documento,
    email = EXCLUDED.email;
SELECT setval('cliente_seq', GREATEST((SELECT COALESCE(MAX(id), 0) FROM public.cliente), 1), true);

INSERT INTO public.veiculo (id, placa, marca, modelo, ano) VALUES
    (1, 'ABC1234', '11111111111', '11111111111', 11111111),
    (2, 'ABC1D23', '11111111111', '11111111111', 11111111)
ON CONFLICT (id) DO UPDATE SET
    placa = EXCLUDED.placa,
    marca = EXCLUDED.marca,
    modelo = EXCLUDED.modelo,
    ano = EXCLUDED.ano;
SELECT setval('veiculo_seq', GREATEST((SELECT COALESCE(MAX(id), 0) FROM public.veiculo), 1), true);

INSERT INTO public.ordem_de_servico (id, cliente_id, veiculo_id, criado_em, atualizado_em) VALUES
    ('2b2276e8-fa72-4f4c-a3b0-2c5b1bf427ef', 1, 1, '2025-12-14 17:28:14.046297 +00:00', '2025-12-14 17:28:14.046297 +00:00'),
    ('1b2276e8-fa72-4f4c-a3b0-2c5b1bf427ef', 1, 1, '2025-10-14 17:20:14.046297 +00:00', '2025-12-14 17:20:14.046297 +00:00'),
    ('f05dd17b-daae-4658-af7c-363dd6e6fdfb', 1, 1, '2025-12-14 17:28:14.714212 +00:00', '2025-12-14 17:28:14.714212 +00:00'),
    ('5b2276e8-fa72-4f4c-a3b0-2c5b1bf427ef', 1, 1, '2024-12-14 17:28:14.714212 +00:00', '2025-12-14 17:28:14.714212 +00:00'),
    ('4b2276e8-fa72-4f4c-a3b0-2c5b1bf427ef', 1, 1, '2025-12-14 17:28:14.714212 +00:00', '2025-12-14 17:28:14.714212 +00:00'),
    ('6b2276e8-fa72-4f4c-a3b0-2c5b1bf427ef', 1, 1, '2025-12-14 17:28:14.714212 +00:00', '2025-12-14 17:28:14.714212 +00:00'),
    ('7b2276e8-fa72-4f4c-a3b0-2c5b1bf427ef', 1, 1, '2025-12-14 17:28:14.714212 +00:00', '2025-12-14 17:28:14.714212 +00:00'),
    ('4298695b-d6ae-45ac-a659-c4de90f81eb4', 2, 2, '2026-01-17 10:00:00.000000 +00:00', '2026-01-17 10:00:00.000000 +00:00')
ON CONFLICT (id) DO UPDATE SET
    cliente_id = EXCLUDED.cliente_id,
    veiculo_id = EXCLUDED.veiculo_id,
    criado_em = EXCLUDED.criado_em,
    atualizado_em = EXCLUDED.atualizado_em;

INSERT INTO public.estado_ordem_servico (ordem_de_servico_id, tipo_estado, data_estado)
SELECT seed.ordem_de_servico_id, seed.tipo_estado, seed.data_estado
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
