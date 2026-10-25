-- =====================================================================
-- Sabor da Gente — catálogo das tabelas NOVAS (pizza montável).
-- Substitui a 120400 neste projeto: não toca em categorias nem produtos
-- (já existem, com as pizzas legadas como produtos 12 a 17).
-- Preços em centavos, iguais aos das pizzas legadas.
-- Itens marcados EXEMPLO devem ser ajustados pela equipe.
-- Idempotente: on conflict do nothing.
-- =====================================================================
begin;

do $$
begin
  if to_regclass('public.tamanhos') is null or to_regclass('public.cupons') is null then
    raise exception 'Aplique antes a 20261016120500_adaptar_schema_existente.';
  end if;
end;
$$;

insert into public.configuracoes (chave, valor) values
  ('taxa_entrega', '500'),          -- R$ 5,00 (EXEMPLO)
  ('regra_preco_pizza', 'maior')    -- 'maior' | 'media'
on conflict do nothing;

insert into public.tamanhos (id, nome, fatias, max_sabores, ordem) values
  (1, 'Média',  6, 2, 1),
  (2, 'Grande', 8, 2, 2)
on conflict do nothing;

insert into public.massas (id, nome, acrescimo) values
  (1, 'Tradicional', 0),
  (2, 'Fina',        0)             -- EXEMPLO
on conflict do nothing;

insert into public.sabores (id, nome, descricao, ingredientes, destaque) values
  (1, 'Calabresa',           'Molho de tomate, queijo, calabresa e cebola.',
      'molho de tomate, mussarela, calabresa, cebola', true),
  (2, 'Frango com Catupiry', 'Molho de tomate, queijo, frango e catupiry.',
      'molho de tomate, mussarela, frango desfiado, catupiry', false),
  (3, 'Portuguesa',          'Queijo, presunto, ovo, cebola, tomate e azeitona.',
      'mussarela, presunto, ovo, cebola, tomate, azeitona', false)
on conflict do nothing;

insert into public.sabor_precos (sabor_id, tamanho_id, preco) values
  (1, 1, 3800), (2, 1, 3800), (3, 1, 4000),   -- Média
  (1, 2, 4500), (2, 2, 4500), (3, 2, 4800)    -- Grande
on conflict do nothing;

insert into public.adicionais (id, nome, preco) values   -- EXEMPLO
  (1, 'Borda de catupiry', 800),
  (2, 'Queijo extra',      500),
  (3, 'Bacon',             600)
on conflict do nothing;

insert into public.cupons (codigo, tipo, valor, valor_minimo_pedido) values   -- EXEMPLO
  ('BEMVINDO10', 'percentual', 10, 3000)
on conflict do nothing;

-- IDs informados à mão: ajusta as sequências
select setval(pg_get_serial_sequence('public.tamanhos',   'id'), (select max(id) from public.tamanhos));
select setval(pg_get_serial_sequence('public.massas',     'id'), (select max(id) from public.massas));
select setval(pg_get_serial_sequence('public.sabores',    'id'), (select max(id) from public.sabores));
select setval(pg_get_serial_sequence('public.adicionais', 'id'), (select max(id) from public.adicionais));

commit;
