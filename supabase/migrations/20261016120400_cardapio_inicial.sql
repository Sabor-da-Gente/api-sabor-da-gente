-- =====================================================================
-- Sabor da Gente — 5/5: cardápio inicial (valores em centavos)
--
-- Mesmos IDs e preços do banco local do app mobile (src/database/seed.ts).
-- Itens marcados com EXEMPLO são sugestões para a equipe ajustar.
-- Fica como migration (e não em seed.sql) para também ser aplicado no
-- projeto da nuvem com `supabase db push`.
-- =====================================================================

insert into public.configuracoes (chave, valor) values
  ('taxa_entrega', '500'),          -- R$ 5,00 (EXEMPLO)
  ('regra_preco_pizza', 'maior');   -- 'maior' | 'media'

insert into public.categorias (id, nome, slug, tipo, icone, ordem) values
  (1, 'Pizzas',     'pizzas',     'pizza',    '🍕', 1),
  (2, 'Esfihas',    'esfihas',    'produtos', '🥟', 2),
  (3, 'Bebidas',    'bebidas',    'produtos', '🥤', 3),
  (4, 'Combos',     'combos',     'produtos', '🎁', 4),
  (5, 'Sobremesas', 'sobremesas', 'produtos', '🍫', 5);

insert into public.tamanhos (id, nome, fatias, max_sabores, ordem) values
  (1, 'Média',  6, 2, 1),   -- EXEMPLO
  (2, 'Grande', 8, 2, 2);

insert into public.massas (id, nome, acrescimo) values
  (1, 'Tradicional', 0),
  (2, 'Fina',        0);    -- EXEMPLO

insert into public.sabores (id, nome, descricao, ingredientes, destaque) values
  (1, 'Calabresa',           'Molho de tomate, queijo, calabresa e cebola.',
      'molho de tomate, mussarela, calabresa, cebola', true),
  (2, 'Frango com Catupiry', 'Molho de tomate, queijo, frango e catupiry.',
      'molho de tomate, mussarela, frango desfiado, catupiry', false),
  (3, 'Portuguesa',          'Queijo, presunto, ovo, cebola, tomate e azeitona.',
      'mussarela, presunto, ovo, cebola, tomate, azeitona', false);

insert into public.sabor_precos (sabor_id, tamanho_id, preco) values
  (1, 2, 4500), (2, 2, 4500), (3, 2, 4800),   -- Grande
  (1, 1, 3800), (2, 1, 3800), (3, 1, 4000);   -- Média (EXEMPLO)

insert into public.adicionais (id, nome, preco) values   -- EXEMPLO
  (1, 'Borda de catupiry', 800),
  (2, 'Queijo extra',      500),
  (3, 'Bacon',             600);

insert into public.produtos (id, categoria_id, nome, descricao, preco, destaque) values
  (1,  2, 'Esfiha de Carne',      'Esfiha saborosa com recheio de carne.',   400, true),
  (2,  2, 'Esfiha de Frango',     'Esfiha recheada com frango temperado.',   400, false),
  (3,  2, 'Esfiha de Queijo',     'Esfiha com recheio cremoso de queijo.',   400, false),
  (4,  2, 'Esfiha de Calabresa',  'Esfiha com calabresa bem temperada.',     400, false),
  (5,  3, 'Coca-Cola 2 litros',   'Refrigerante Coca-Cola para compartilhar.', 1500, false),
  (6,  3, 'Guaraná 1 litro',      'Refrigerante de guaraná, ideal para acompanhar seu pedido.', 800, false),
  (7,  3, 'Refrigerante pequeno', 'Refrigerante em embalagem pequena.',      400, false),
  (8,  4, 'Combo Esfihas',        '10 esfihas sortidas + Guaraná 1 litro.', 4000, true),   -- EXEMPLO
  (9,  5, 'Brigadeiro',           'Doce de chocolate coberto com granulado.', 300, false),
  (10, 5, 'Pudim',                'Pudim de leite condensado com calda de caramelo.', 600, false),
  (11, 5, 'Mousse de chocolate',  'Sobremesa cremosa e deliciosa de chocolate.', 500, false);

insert into public.cupons (codigo, tipo, valor, valor_minimo_pedido) values   -- EXEMPLO
  ('BEMVINDO10', 'percentual', 10, 3000);

-- IDs foram informados à mão: ajusta as sequências para os próximos cadastros
select setval(pg_get_serial_sequence('public.categorias', 'id'), (select max(id) from public.categorias));
select setval(pg_get_serial_sequence('public.tamanhos',   'id'), (select max(id) from public.tamanhos));
select setval(pg_get_serial_sequence('public.massas',     'id'), (select max(id) from public.massas));
select setval(pg_get_serial_sequence('public.sabores',    'id'), (select max(id) from public.sabores));
select setval(pg_get_serial_sequence('public.adicionais', 'id'), (select max(id) from public.adicionais));
select setval(pg_get_serial_sequence('public.produtos',   'id'), (select max(id) from public.produtos));
