-- =====================================================================
-- Sabor da Gente — dados iniciais (cardápio de teste)
-- Os itens e preços vieram do app mobile atual.
-- Linhas marcadas com "EXEMPLO" são sugestões para a equipe ajustar.
--
-- O usuário administrador NÃO é criado aqui, porque a senha precisa
-- de hash (bcrypt). Crie-o pelo script de seed do backend.
-- =====================================================================

PRAGMA foreign_keys = ON;

INSERT INTO configuracoes (chave, valor) VALUES
  ('taxa_entrega', '500'),          -- R$ 5,00 (EXEMPLO)
  ('regra_preco_pizza', 'maior');   -- 'maior' | 'media' — ver docs/modelo-de-dados.md

INSERT INTO categorias (id, nome, slug, tipo, icone, ordem) VALUES
  (1, 'Pizzas',     'pizzas',     'pizza',    '🍕', 1),
  (2, 'Esfihas',    'esfihas',    'produtos', '🥟', 2),
  (3, 'Bebidas',    'bebidas',    'produtos', '🥤', 3),
  (4, 'Combos',     'combos',     'produtos', '🎁', 4),
  (5, 'Sobremesas', 'sobremesas', 'produtos', '🍫', 5);

-- Pizza --------------------------------------------------------------
INSERT INTO tamanhos (id, nome, fatias, max_sabores, ordem) VALUES
  (1, 'Média',  6, 2, 1),   -- EXEMPLO (o app hoje só tem Grande)
  (2, 'Grande', 8, 2, 2);

INSERT INTO massas (id, nome, acrescimo) VALUES
  (1, 'Tradicional', 0),
  (2, 'Fina',        0);    -- EXEMPLO

INSERT INTO sabores (id, nome, descricao, ingredientes, destaque) VALUES
  (1, 'Calabresa',           'Molho de tomate, queijo, calabresa e cebola.',
      'molho de tomate, mussarela, calabresa, cebola', 1),
  (2, 'Frango com Catupiry', 'Molho de tomate, queijo, frango e catupiry.',
      'molho de tomate, mussarela, frango desfiado, catupiry', 0),
  (3, 'Portuguesa',          'Queijo, presunto, ovo, cebola, tomate e azeitona.',
      'mussarela, presunto, ovo, cebola, tomate, azeitona', 0);

INSERT INTO sabor_precos (sabor_id, tamanho_id, preco) VALUES
  (1, 2, 4500), (2, 2, 4500), (3, 2, 4800),   -- Grande (preços do app)
  (1, 1, 3800), (2, 1, 3800), (3, 1, 4000);   -- Média  (EXEMPLO)

INSERT INTO adicionais (id, nome, preco) VALUES   -- EXEMPLO
  (1, 'Borda de catupiry', 800),
  (2, 'Queijo extra',      500),
  (3, 'Bacon',             600);

-- Produtos de preço fixo ---------------------------------------------
INSERT INTO produtos (categoria_id, nome, descricao, preco, destaque) VALUES
  (2, 'Esfiha de Carne',     'Esfiha saborosa com recheio de carne.',   400, 1),
  (2, 'Esfiha de Frango',    'Esfiha recheada com frango temperado.',   400, 0),
  (2, 'Esfiha de Queijo',    'Esfiha com recheio cremoso de queijo.',   400, 0),
  (2, 'Esfiha de Calabresa', 'Esfiha com calabresa bem temperada.',     400, 0),
  (3, 'Coca-Cola 2 litros',  'Refrigerante Coca-Cola para compartilhar.', 1500, 0),
  (3, 'Guaraná 1 litro',     'Refrigerante de guaraná, ideal para acompanhar seu pedido.', 800, 0),
  (3, 'Refrigerante pequeno','Refrigerante em embalagem pequena.',      400, 0),
  (4, 'Combo Esfihas',       '10 esfihas sortidas + Guaraná 1 litro.', 4000, 1), -- EXEMPLO
  (5, 'Brigadeiro',          'Doce de chocolate coberto com granulado.', 300, 0),
  (5, 'Pudim',               'Pudim de leite condensado com calda de caramelo.', 600, 0),
  (5, 'Mousse de chocolate', 'Sobremesa cremosa e deliciosa de chocolate.', 500, 0);

INSERT INTO cupons (codigo, tipo, valor, valor_minimo_pedido) VALUES   -- EXEMPLO
  ('BEMVINDO10', 'percentual', 10, 3000);
