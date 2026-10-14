-- =====================================================================
-- Sabor da Gente — esquema do banco (SQLite)
-- Repositório: sabor-da-gente-api
--
-- Convenções:
--   * Valores em dinheiro: INTEGER em CENTAVOS (R$ 45,00 = 4500).
--   * Datas: TEXT no formato ISO 8601 UTC (ex.: 2026-10-14T13:00:00Z).
--   * Booleanos: INTEGER 0/1.
--   * Registros de catálogo nunca são apagados: usa-se ativo = 0.
--   * Pedidos guardam "fotografias" (snapshots) de nomes e preços,
--     para que mudanças no cardápio não alterem pedidos antigos.
-- =====================================================================

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------
-- USUÁRIOS (Cliente e Administrador são o mesmo registro, diferenciados
-- pela coluna tipo — herança "tabela única")
-- ---------------------------------------------------------------------
CREATE TABLE usuarios (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  nome          TEXT    NOT NULL,
  email         TEXT    NOT NULL UNIQUE COLLATE NOCASE,
  senha_hash    TEXT    NOT NULL,
  telefone      TEXT,
  tipo          TEXT    NOT NULL DEFAULT 'cliente'
                CHECK (tipo IN ('cliente', 'admin')),
  ativo         INTEGER NOT NULL DEFAULT 1 CHECK (ativo IN (0, 1)),
  criado_em     TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  atualizado_em TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

CREATE TABLE enderecos (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  usuario_id  INTEGER NOT NULL REFERENCES usuarios(id),
  apelido     TEXT,                       -- "Casa", "Trabalho"
  logradouro  TEXT    NOT NULL,
  numero      TEXT    NOT NULL,
  complemento TEXT,
  bairro      TEXT    NOT NULL,
  cidade      TEXT    NOT NULL,
  uf          TEXT    NOT NULL DEFAULT 'PB' CHECK (length(uf) = 2),
  cep         TEXT,
  referencia  TEXT,
  principal   INTEGER NOT NULL DEFAULT 0 CHECK (principal IN (0, 1)),
  ativo       INTEGER NOT NULL DEFAULT 1 CHECK (ativo IN (0, 1)),
  criado_em   TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);
CREATE INDEX idx_enderecos_usuario ON enderecos(usuario_id);

-- ---------------------------------------------------------------------
-- CATÁLOGO
-- ---------------------------------------------------------------------
CREATE TABLE categorias (
  id     INTEGER PRIMARY KEY AUTOINCREMENT,
  nome   TEXT    NOT NULL UNIQUE,
  slug   TEXT    NOT NULL UNIQUE,          -- "pizzas", "esfihas"...
  -- 'pizza': a categoria abre o "Monte sua pizza" (tamanhos/sabores);
  -- 'produtos': lista produtos de preço fixo.
  tipo   TEXT    NOT NULL DEFAULT 'produtos' CHECK (tipo IN ('pizza', 'produtos')),
  icone  TEXT,                             -- emoji ou nome de ícone
  ordem  INTEGER NOT NULL DEFAULT 0,
  ativa  INTEGER NOT NULL DEFAULT 1 CHECK (ativa IN (0, 1))
);

-- Produtos de preço fixo: esfihas, bebidas, sobremesas, combos.
CREATE TABLE produtos (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  categoria_id  INTEGER NOT NULL REFERENCES categorias(id),
  nome          TEXT    NOT NULL,
  descricao     TEXT,
  ingredientes  TEXT,
  imagem_url    TEXT,
  preco         INTEGER NOT NULL CHECK (preco >= 0),
  destaque      INTEGER NOT NULL DEFAULT 0 CHECK (destaque IN (0, 1)),
  ativo         INTEGER NOT NULL DEFAULT 1 CHECK (ativo IN (0, 1)),
  criado_em     TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  atualizado_em TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);
CREATE INDEX idx_produtos_categoria ON produtos(categoria_id);

-- ---------------------------------------------------------------------
-- PIZZA MONTÁVEL: tamanho + massa + 1..N sabores + adicionais
-- ---------------------------------------------------------------------
CREATE TABLE tamanhos (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  nome        TEXT    NOT NULL UNIQUE,     -- "Média", "Grande"
  fatias      INTEGER NOT NULL CHECK (fatias > 0),
  max_sabores INTEGER NOT NULL DEFAULT 1 CHECK (max_sabores BETWEEN 1 AND 4),
  ordem       INTEGER NOT NULL DEFAULT 0,
  ativo       INTEGER NOT NULL DEFAULT 1 CHECK (ativo IN (0, 1))
);

CREATE TABLE massas (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  nome       TEXT    NOT NULL UNIQUE,      -- "Tradicional", "Fina"
  acrescimo  INTEGER NOT NULL DEFAULT 0 CHECK (acrescimo >= 0),
  ativo      INTEGER NOT NULL DEFAULT 1 CHECK (ativo IN (0, 1))
);

CREATE TABLE sabores (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  nome         TEXT    NOT NULL UNIQUE,
  descricao    TEXT,
  ingredientes TEXT,
  imagem_url   TEXT,
  destaque     INTEGER NOT NULL DEFAULT 0 CHECK (destaque IN (0, 1)),
  ativo        INTEGER NOT NULL DEFAULT 1 CHECK (ativo IN (0, 1))
);

-- Preço de cada sabor em cada tamanho.
-- Sem linha aqui = sabor indisponível naquele tamanho.
CREATE TABLE sabor_precos (
  sabor_id   INTEGER NOT NULL REFERENCES sabores(id),
  tamanho_id INTEGER NOT NULL REFERENCES tamanhos(id),
  preco      INTEGER NOT NULL CHECK (preco >= 0),
  PRIMARY KEY (sabor_id, tamanho_id)
);

CREATE TABLE adicionais (
  id     INTEGER PRIMARY KEY AUTOINCREMENT,
  nome   TEXT    NOT NULL UNIQUE,          -- "Borda de catupiry", "Bacon extra"
  preco  INTEGER NOT NULL CHECK (preco >= 0),
  ativo  INTEGER NOT NULL DEFAULT 1 CHECK (ativo IN (0, 1))
);

-- ---------------------------------------------------------------------
-- CUPONS (opcional — fase 2)
-- ---------------------------------------------------------------------
CREATE TABLE cupons (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  codigo              TEXT    NOT NULL UNIQUE COLLATE NOCASE,
  tipo                TEXT    NOT NULL CHECK (tipo IN ('percentual', 'valor_fixo')),
  valor               INTEGER NOT NULL CHECK (valor > 0), -- % (1..100) ou centavos
  valor_minimo_pedido INTEGER NOT NULL DEFAULT 0,
  valido_de           TEXT,
  valido_ate          TEXT,
  usos_maximos        INTEGER,                            -- NULL = ilimitado
  ativo               INTEGER NOT NULL DEFAULT 1 CHECK (ativo IN (0, 1)),
  CHECK (tipo <> 'percentual' OR valor <= 100)
);

-- ---------------------------------------------------------------------
-- PEDIDOS
-- ---------------------------------------------------------------------
CREATE TABLE pedidos (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  cliente_id       INTEGER NOT NULL REFERENCES usuarios(id),
  tipo_entrega     TEXT    NOT NULL CHECK (tipo_entrega IN ('entrega', 'retirada')),
  endereco_id      INTEGER REFERENCES enderecos(id),
  endereco_entrega TEXT,      -- snapshot do endereço no momento do pedido
  status           TEXT    NOT NULL DEFAULT 'realizado'
                   CHECK (status IN ('realizado', 'em_preparacao', 'saiu_para_entrega',
                                     'pronto_para_retirada', 'entregue', 'cancelado')),
  observacao       TEXT,
  cupom_id         INTEGER REFERENCES cupons(id),
  subtotal         INTEGER NOT NULL CHECK (subtotal >= 0),
  desconto         INTEGER NOT NULL DEFAULT 0 CHECK (desconto >= 0),
  taxa_entrega     INTEGER NOT NULL DEFAULT 0 CHECK (taxa_entrega >= 0),
  total            INTEGER NOT NULL CHECK (total >= 0),
  criado_em        TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  atualizado_em    TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  CHECK (tipo_entrega = 'retirada' OR (endereco_id IS NOT NULL AND endereco_entrega IS NOT NULL)),
  CHECK (total = subtotal - desconto + taxa_entrega)
);
CREATE INDEX idx_pedidos_cliente ON pedidos(cliente_id);
CREATE INDEX idx_pedidos_status  ON pedidos(status);
CREATE INDEX idx_pedidos_data    ON pedidos(criado_em);

-- Cada linha do pedido. tipo = 'produto' (preço fixo) ou 'pizza' (montada).
CREATE TABLE itens_pedido (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  pedido_id      INTEGER NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
  tipo           TEXT    NOT NULL CHECK (tipo IN ('produto', 'pizza')),
  produto_id     INTEGER REFERENCES produtos(id),
  tamanho_id     INTEGER REFERENCES tamanhos(id),
  massa_id       INTEGER REFERENCES massas(id),
  descricao      TEXT    NOT NULL,   -- snapshot: "Pizza Grande — Calabresa / Portuguesa"
  quantidade     INTEGER NOT NULL CHECK (quantidade BETWEEN 1 AND 50),
  preco_unitario INTEGER NOT NULL CHECK (preco_unitario >= 0),
  subtotal       INTEGER NOT NULL CHECK (subtotal >= 0),
  observacao     TEXT,
  CHECK (
    (tipo = 'produto' AND produto_id IS NOT NULL AND tamanho_id IS NULL AND massa_id IS NULL)
    OR
    (tipo = 'pizza' AND produto_id IS NULL AND tamanho_id IS NOT NULL AND massa_id IS NOT NULL)
  ),
  CHECK (subtotal = preco_unitario * quantidade)
);
CREATE INDEX idx_itens_pedido ON itens_pedido(pedido_id);

CREATE TABLE itens_pedido_sabores (
  item_id    INTEGER NOT NULL REFERENCES itens_pedido(id) ON DELETE CASCADE,
  sabor_id   INTEGER NOT NULL REFERENCES sabores(id),
  nome       TEXT    NOT NULL,   -- snapshot
  preco      INTEGER NOT NULL,   -- snapshot do preço do sabor no tamanho
  PRIMARY KEY (item_id, sabor_id)
);

CREATE TABLE itens_pedido_adicionais (
  item_id      INTEGER NOT NULL REFERENCES itens_pedido(id) ON DELETE CASCADE,
  adicional_id INTEGER NOT NULL REFERENCES adicionais(id),
  nome         TEXT    NOT NULL, -- snapshot
  preco        INTEGER NOT NULL, -- snapshot
  PRIMARY KEY (item_id, adicional_id)
);

-- Linha do tempo do acompanhamento ("Pedido realizado → Em preparação → ...")
CREATE TABLE pedido_status_historico (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  pedido_id   INTEGER NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
  status      TEXT    NOT NULL,
  alterado_por INTEGER REFERENCES usuarios(id),
  criado_em   TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);
CREATE INDEX idx_historico_pedido ON pedido_status_historico(pedido_id);

-- Pagamento simulado (1 por pedido)
CREATE TABLE pagamentos (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  pedido_id  INTEGER NOT NULL UNIQUE REFERENCES pedidos(id) ON DELETE CASCADE,
  forma      TEXT    NOT NULL CHECK (forma IN ('pix', 'cartao', 'dinheiro')),
  status     TEXT    NOT NULL DEFAULT 'pendente'
             CHECK (status IN ('pendente', 'aprovado', 'recusado', 'estornado')),
  valor      INTEGER NOT NULL CHECK (valor >= 0),
  troco_para INTEGER,            -- só para dinheiro
  criado_em  TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  CHECK (troco_para IS NULL OR (forma = 'dinheiro' AND troco_para >= valor))
);

-- ---------------------------------------------------------------------
-- FAVORITOS (opcional — fase 2): produto OU sabor de pizza
-- ---------------------------------------------------------------------
CREATE TABLE favoritos (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  usuario_id INTEGER NOT NULL REFERENCES usuarios(id),
  produto_id INTEGER REFERENCES produtos(id),
  sabor_id   INTEGER REFERENCES sabores(id),
  criado_em  TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  CHECK ((produto_id IS NULL) <> (sabor_id IS NULL))
);
CREATE UNIQUE INDEX uq_favorito_produto ON favoritos(usuario_id, produto_id) WHERE produto_id IS NOT NULL;
CREATE UNIQUE INDEX uq_favorito_sabor   ON favoritos(usuario_id, sabor_id)   WHERE sabor_id   IS NOT NULL;

-- ---------------------------------------------------------------------
-- CONFIGURAÇÕES GERAIS (chave/valor)
-- ---------------------------------------------------------------------
CREATE TABLE configuracoes (
  chave TEXT PRIMARY KEY,
  valor TEXT NOT NULL
);
