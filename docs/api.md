# Contrato da API — Sabor da Gente

Este arquivo é a **referência oficial** entre os três repositórios:

| Repositório | Usa a API para |
|---|---|
| `sabor-da-gente-mobile` (PDM) | cardápio, carrinho → pedido, acompanhamento, perfil |
| `sabor-da-gente-web` (DAW III) | painel admin: pedidos, produtos, clientes, estatísticas |
| `sabor-da-gente-api` (DAW III) | implementa tudo isto + banco SQLite |

> **Regra de ouro:** mudou algo aqui → abrir issue nos repositórios afetados.
> Prefira **acrescentar** campos a renomear ou remover.

Modelo do banco e regras de negócio (R1…R9): [`modelo-de-dados.md`](modelo-de-dados.md).

---

## 1. Convenções gerais

- **Base URL:** `http://<ip-do-computador>:3333` em desenvolvimento (no celular, nunca `localhost`).
  Mobile: `EXPO_PUBLIC_API_URL`. Web: variável equivalente.
- **Formato:** JSON, `Content-Type: application/json`.
- **Nomes:** JSON em `camelCase`; banco em `snake_case` (a API converte).
- **Dinheiro:** inteiro em **centavos** (`4500` = R$ 45,00). Quem exibe formata.
- **Datas:** ISO 8601 UTC (`"2026-10-14T13:00:00Z"`).
- **IDs:** inteiros.
- **Autenticação:** `Authorization: Bearer <token>` (JWT, validade sugerida 7 dias).
  Token traz `{ id, tipo }`.
- **CORS:** liberar a origem do painel web.

### Níveis de acesso
| Marca | Quem |
|---|---|
| 🌐 público | sem token |
| 👤 cliente | token de cliente |
| 🛠️ admin | token de admin |

### Paginação (listas grandes)
`?pagina=1&limite=20` → resposta:
```json
{ "dados": [ ... ], "pagina": 1, "limite": 20, "total": 57 }
```

### Erros — sempre neste formato
```json
{
  "erro": {
    "codigo": "VALIDACAO",
    "mensagem": "Escolha no máximo 2 sabores para o tamanho Grande.",
    "detalhes": [ { "campo": "itens[0].saborIds", "mensagem": "máximo 2" } ]
  }
}
```

| HTTP | `codigo` | Quando |
|---|---|---|
| 400 | `VALIDACAO` | corpo inválido, regra de negócio violada |
| 401 | `NAO_AUTENTICADO` | sem token / token inválido / expirado |
| 403 | `SEM_PERMISSAO` | cliente acessando rota admin ou pedido de outro cliente |
| 404 | `NAO_ENCONTRADO` | recurso não existe (ou está inativo, no catálogo público) |
| 409 | `CONFLITO` | e-mail já cadastrado, favorito duplicado |
| 409 | `TRANSICAO_INVALIDA` | mudança de status fora do fluxo (R7) |
| 422 | `INDISPONIVEL` | produto/sabor/tamanho inativo no momento do pedido |
| 500 | `ERRO_INTERNO` | erro inesperado (mensagem genérica) |

---

## 2. Objetos (formatos de resposta)

### Usuario
```json
{ "id": 1, "nome": "Ana Souza", "email": "ana@email.com", "telefone": "83999990000",
  "tipo": "cliente", "criadoEm": "2026-10-14T13:00:00Z" }
```
`senhaHash` **nunca** é retornado.

### Endereco
```json
{ "id": 3, "apelido": "Casa", "logradouro": "Rua Solon de Lucena", "numero": "120",
  "complemento": "Apto 2", "bairro": "Centro", "cidade": "Esperança", "uf": "PB",
  "cep": "58135-000", "referencia": "Perto da praça", "principal": true }
```

### Categoria
```json
{ "id": 1, "nome": "Pizzas", "slug": "pizzas", "tipo": "pizza", "icone": "🍕", "ordem": 1 }
```

### Produto
```json
{ "id": 1, "categoriaId": 2, "nome": "Esfiha de Carne",
  "descricao": "Esfiha saborosa com recheio de carne.", "ingredientes": null,
  "imagemUrl": null, "preco": 400, "destaque": true, "ativo": true }
```

### Pedido (completo)
```json
{
  "id": 42,
  "status": "em_preparacao",
  "tipoEntrega": "entrega",
  "enderecoEntrega": "Rua Solon de Lucena, 120, Apto 2 — Centro, Esperança/PB",
  "observacao": "Sem cebola, por favor",
  "cliente": { "id": 1, "nome": "Ana Souza", "telefone": "83999990000" },
  "itens": [
    {
      "id": 101, "tipo": "pizza",
      "descricao": "Pizza Grande (Tradicional) — Calabresa / Portuguesa",
      "tamanho": { "id": 2, "nome": "Grande" },
      "massa": { "id": 1, "nome": "Tradicional" },
      "sabores": [ { "id": 1, "nome": "Calabresa", "preco": 4500 },
                   { "id": 3, "nome": "Portuguesa", "preco": 4800 } ],
      "adicionais": [ { "id": 1, "nome": "Borda de catupiry", "preco": 800 } ],
      "quantidade": 1, "precoUnitario": 5600, "subtotal": 5600, "observacao": null
    },
    {
      "id": 102, "tipo": "produto", "produtoId": 1,
      "descricao": "Esfiha de Carne",
      "quantidade": 6, "precoUnitario": 400, "subtotal": 2400, "observacao": null
    }
  ],
  "cupom": null,
  "subtotal": 8000, "desconto": 0, "taxaEntrega": 500, "total": 8500,
  "pagamento": { "forma": "dinheiro", "status": "pendente", "valor": 8500, "trocoPara": 10000 },
  "historicoStatus": [
    { "status": "realizado",     "em": "2026-10-14T22:01:00Z" },
    { "status": "em_preparacao", "em": "2026-10-14T22:05:00Z" }
  ],
  "criadoEm": "2026-10-14T22:01:00Z",
  "atualizadoEm": "2026-10-14T22:05:00Z"
}
```

### PedidoResumo (listas)
```json
{ "id": 42, "status": "em_preparacao", "tipoEntrega": "entrega", "total": 8500,
  "quantidadeItens": 7, "clienteNome": "Ana Souza", "criadoEm": "2026-10-14T22:01:00Z" }
```

### Status do pedido
| Valor | Texto para exibir |
|---|---|
| `realizado` | Pedido realizado |
| `em_preparacao` | Em preparação |
| `saiu_para_entrega` | Saiu para entrega |
| `pronto_para_retirada` | Pronto para retirada |
| `entregue` | Entregue |
| `cancelado` | Cancelado |

---

## 3. Autenticação

### `POST /auth/cadastro` 🌐
Cria **cliente** (admin nunca é criado por aqui).
```json
{ "nome": "Ana Souza", "email": "ana@email.com", "senha": "minhasenha", "telefone": "83999990000" }
```
Validação: nome ≥ 2 caracteres, e-mail válido e único, senha ≥ 6, telefone obrigatório.
**201** → `{ "token": "eyJ...", "usuario": Usuario }` · **409** e-mail já cadastrado.

### `POST /auth/login` 🌐
```json
{ "email": "ana@email.com", "senha": "minhasenha" }
```
**200** → `{ "token": "eyJ...", "usuario": Usuario }` · **401** credenciais inválidas (mensagem genérica, sem dizer qual campo errou).
O painel web deve recusar entrada se `usuario.tipo !== "admin"`.

### `GET /auth/me` 👤🛠️
**200** → `Usuario`

### `PATCH /auth/me` 👤
Atualiza `nome`, `telefone` e/ou `senha` (exige `senhaAtual` para trocar senha). **200** → `Usuario`

---

## 4. Catálogo (mobile e web)

Rotas públicas retornam **só itens ativos**.

### `GET /categorias` 🌐
**200** → `Categoria[]` (ordenado por `ordem`)

### `GET /produtos` 🌐
Filtros: `?categoria=esfihas` (slug) · `?destaque=true` · `?busca=coca`
**200** → `Produto[]`

### `GET /produtos/:id` 🌐
**200** → `Produto` · **404**

### `GET /pizzas/opcoes` 🌐
Tudo que a tela "Monte sua pizza" precisa, numa chamada:
```json
{
  "regraPreco": "maior",
  "tamanhos": [
    { "id": 1, "nome": "Média",  "fatias": 6, "maxSabores": 2 },
    { "id": 2, "nome": "Grande", "fatias": 8, "maxSabores": 2 }
  ],
  "massas": [ { "id": 1, "nome": "Tradicional", "acrescimo": 0 },
              { "id": 2, "nome": "Fina", "acrescimo": 0 } ],
  "sabores": [
    { "id": 1, "nome": "Calabresa", "descricao": "...", "ingredientes": "...",
      "imagemUrl": null, "destaque": true,
      "precos": [ { "tamanhoId": 1, "preco": 3800 }, { "tamanhoId": 2, "preco": 4500 } ] }
  ],
  "adicionais": [ { "id": 1, "nome": "Borda de catupiry", "preco": 800 } ]
}
```
O app pode **mostrar** o preço estimado com `regraPreco`, mas o valor oficial é o de `/pedidos/calcular`.

### `GET /destaques` 🌐
Para a tela inicial ("mais pedidos"/promoções).
**200** → `{ "produtos": Produto[], "sabores": Sabor[] }`

---

## 5. Pedidos — cliente

### Corpo de um pedido (`NovoPedido`)
Usado por `/pedidos/calcular` e `/pedidos`. **Sem preços** — a API calcula (R3).
```json
{
  "itens": [
    { "tipo": "pizza", "tamanhoId": 2, "massaId": 1, "saborIds": [1, 3],
      "adicionalIds": [1], "quantidade": 1, "observacao": "Bem assada" },
    { "tipo": "produto", "produtoId": 1, "quantidade": 6 }
  ],
  "tipoEntrega": "entrega",
  "enderecoId": 3,
  "pagamento": { "forma": "dinheiro", "trocoPara": 10000 },
  "cupom": "BEMVINDO10",
  "observacao": "Sem cebola, por favor"
}
```

| Campo | Regras |
|---|---|
| `itens` | 1 a 30 itens |
| `itens[].quantidade` | 1 a 50 |
| pizza `saborIds` | 1..`maxSabores` do tamanho, sem repetir, todos com preço no tamanho (R2) |
| pizza `massaId` | obrigatório |
| pizza `adicionalIds` | opcional, sem repetir |
| `tipoEntrega` | `entrega` exige `enderecoId` do próprio cliente (R5); `retirada` ignora endereço |
| `pagamento.forma` | `pix` · `cartao` · `dinheiro` |
| `pagamento.trocoPara` | só com `dinheiro`, ≥ total |
| `cupom` | opcional *(fase 2)* |
| `observacao` | até 300 caracteres (itens: até 200) |

### `POST /pedidos/calcular` 👤
Simula sem gravar. Usar na tela de revisão, antes de "Confirmar".
**200** →
```json
{
  "itens": [
    { "descricao": "Pizza Grande (Tradicional) — Calabresa / Portuguesa",
      "quantidade": 1, "precoUnitario": 5600, "subtotal": 5600 },
    { "descricao": "Esfiha de Carne", "quantidade": 6, "precoUnitario": 400, "subtotal": 2400 }
  ],
  "subtotal": 8000, "desconto": 800, "taxaEntrega": 500, "total": 7700,
  "avisos": []
}
```
`avisos` traz mensagens não bloqueantes (ex.: `"Cupom BEMVINDO10 aplicado: 10%"`).
**400** `VALIDACAO` · **422** `INDISPONIVEL`

### `POST /pedidos` 👤
Mesmo corpo. Grava tudo numa transação (R9), status inicial `realizado`.
**201** → `Pedido` (completo) · **400** · **422**

> Depois do 201 o app limpa o carrinho (AsyncStorage) e abre o acompanhamento.

### `GET /meus-pedidos` 👤
Histórico do cliente logado, mais recentes primeiro. Paginado.
**200** → `{ "dados": PedidoResumo[], ... }`

### `GET /pedidos/:id` 👤🛠️
Cliente só vê os próprios (senão **403**). Admin vê qualquer um.
**200** → `Pedido`

**Acompanhamento:** o app consulta esta rota a cada ~15 s enquanto o status não for `entregue` ou `cancelado`.

### `POST /pedidos/:id/cancelar` 👤
Só se `status = realizado` (R7). **200** → `Pedido` · **409** `TRANSICAO_INVALIDA`

---

## 6. Endereços — cliente

| Método | Rota | Corpo / Resposta |
|---|---|---|
| `GET` | `/enderecos` 👤 | → `Endereco[]` (só ativos) |
| `POST` | `/enderecos` 👤 | `Endereco` sem `id` → **201** `Endereco` |
| `PUT` | `/enderecos/:id` 👤 | `Endereco` sem `id` → **200** `Endereco` |
| `DELETE` | `/enderecos/:id` 👤 | → **204** (marca `ativo = 0`) |

Obrigatórios: `logradouro`, `numero`, `bairro`, `cidade`. Marcar `principal: true` desmarca os outros.

---

## 7. Favoritos — cliente *(fase 2)*

| Método | Rota | Corpo / Resposta |
|---|---|---|
| `GET` | `/favoritos` 👤 | → `{ "produtos": Produto[], "sabores": Sabor[] }` |
| `POST` | `/favoritos` 👤 | `{ "produtoId": 1 }` **ou** `{ "saborId": 3 }` → **201** · **409** se já existe |
| `DELETE` | `/favoritos/produto/:id` ou `/favoritos/sabor/:id` 👤 | → **204** |

---

## 8. Painel administrativo (web) 🛠️

Todas exigem token de admin. Rotas sob `/admin`.

### Pedidos
| Método | Rota | Descrição |
|---|---|---|
| `GET` | `/admin/pedidos` | Filtros: `?status=realizado,em_preparacao` `?de=2026-10-01&ate=2026-10-14` `?clienteId=1`. Paginado → `PedidoResumo[]` |
| `GET` | `/admin/pedidos/:id` | → `Pedido` |
| `PATCH` | `/admin/pedidos/:id/status` | `{ "status": "em_preparacao" }` → **200** `Pedido` · **409** `TRANSICAO_INVALIDA` |
| `PATCH` | `/admin/pedidos/:id/pagamento` | `{ "status": "aprovado" }` → **200** `Pedido` |

Sugestão para o painel: atualizar a lista a cada ~10 s para ver pedidos novos.

### Catálogo
Mesmo padrão para todos os recursos abaixo:

| Método | Rota | Descrição |
|---|---|---|
| `GET` | `/admin/<recurso>` | Lista **inclusive inativos** (`?ativo=true/false`) |
| `POST` | `/admin/<recurso>` | Cria → **201** |
| `PUT` | `/admin/<recurso>/:id` | Edita → **200** |
| `PATCH` | `/admin/<recurso>/:id/ativo` | `{ "ativo": false }` desativa / reativa → **200** |

Recursos: `categorias`, `produtos`, `sabores`, `tamanhos`, `massas`, `adicionais`, `cupons`.

Não há `DELETE` no catálogo: desativar preserva os pedidos antigos.

Preços de sabor por tamanho:
```
PUT /admin/sabores/:id/precos
[ { "tamanhoId": 1, "preco": 3800 }, { "tamanhoId": 2, "preco": 4500 } ]
```
Substitui todos os preços daquele sabor. Tamanho fora da lista = sabor indisponível nele.

### Clientes
| Método | Rota | Descrição |
|---|---|---|
| `GET` | `/admin/clientes` | `?busca=ana` · paginado → `Usuario[]` + `totalPedidos`, `ultimoPedidoEm` |
| `GET` | `/admin/clientes/:id` | → `Usuario` + `enderecos` + últimos pedidos (`PedidoResumo[]`) |

### Estatísticas
`GET /admin/estatisticas?de=2026-10-01&ate=2026-10-31`
```json
{
  "periodo": { "de": "2026-10-01", "ate": "2026-10-31" },
  "pedidos": 128, "cancelados": 4,
  "faturamento": 742000, "ticketMedio": 5984,
  "porStatus": { "realizado": 2, "em_preparacao": 1, "entregue": 121, "cancelado": 4 },
  "porDia": [ { "data": "2026-10-01", "pedidos": 5, "faturamento": 28000 } ],
  "maisVendidos": [
    { "tipo": "sabor",   "id": 1, "nome": "Calabresa",       "quantidade": 64 },
    { "tipo": "produto", "id": 1, "nome": "Esfiha de Carne", "quantidade": 210 }
  ]
}
```
Faturamento conta só pedidos **não cancelados**.

### Configurações
| Método | Rota | Corpo |
|---|---|---|
| `GET` | `/admin/configuracoes` | → `{ "taxaEntrega": 500, "regraPrecoPizza": "maior" }` |
| `PUT` | `/admin/configuracoes` | mesmo formato |

---

## 9. Resumo de rotas

| # | Método | Rota | Acesso | Fase | Quem usa |
|---|---|---|---|---|---|
| 1 | POST | `/auth/cadastro` | 🌐 | 1 | mobile |
| 2 | POST | `/auth/login` | 🌐 | 1 | mobile, web |
| 3 | GET | `/auth/me` | 👤🛠️ | 1 | mobile, web |
| 4 | PATCH | `/auth/me` | 👤 | 1 | mobile |
| 5 | GET | `/categorias` | 🌐 | 1 | mobile |
| 6 | GET | `/produtos` | 🌐 | 1 | mobile |
| 7 | GET | `/produtos/:id` | 🌐 | 1 | mobile |
| 8 | GET | `/pizzas/opcoes` | 🌐 | 1 | mobile |
| 9 | GET | `/destaques` | 🌐 | 1 | mobile |
| 10 | POST | `/pedidos/calcular` | 👤 | 1 | mobile |
| 11 | POST | `/pedidos` | 👤 | 1 | mobile |
| 12 | GET | `/meus-pedidos` | 👤 | 1 | mobile |
| 13 | GET | `/pedidos/:id` | 👤🛠️ | 1 | mobile |
| 14 | POST | `/pedidos/:id/cancelar` | 👤 | 1 | mobile |
| 15 | CRUD | `/enderecos` | 👤 | 1 | mobile |
| 16 | GET/PATCH | `/admin/pedidos…` | 🛠️ | 1 | web |
| 17 | CRUD | `/admin/<catálogo>` | 🛠️ | 1 | web |
| 18 | GET | `/admin/clientes…` | 🛠️ | 1 | web |
| 19 | GET | `/admin/estatisticas` | 🛠️ | 1 | web |
| 20 | GET/PUT | `/admin/configuracoes` | 🛠️ | 1 | web |
| 21 | CRUD | `/favoritos` | 👤 | 2 | mobile |
| 22 | CRUD | `/admin/cupons` + campo `cupom` | 🛠️👤 | 2 | web, mobile |

### Ordem sugerida de implementação
1. `GET /categorias`, `/produtos`, `/pizzas/opcoes` → mobile mostra o cardápio real.
2. `/auth/*` + `/enderecos`.
3. `POST /pedidos/calcular` e `POST /pedidos` → mobile envia pedidos.
4. `GET /pedidos/:id`, `/meus-pedidos` → acompanhamento e histórico.
5. `/admin/pedidos` + status → painel web funcionando.
6. CRUD do catálogo, clientes, estatísticas.
7. Fase 2: cupons, favoritos.

---

## 10. Impacto no app mobile atual

| Hoje no app | Passa a ser |
|---|---|
| Produtos fixos em cada tela | `GET /produtos?categoria=…` e `GET /pizzas/opcoes` |
| `ItemCarrinho { nome, sabores, preco }` | guardar também `tipo`, `produtoId` **ou** `tamanhoId/massaId/saborIds/adicionalIds`, e `observacao` |
| Esfiha com o nome em `sabores` | esfiha é `{ tipo: "produto", produtoId }` |
| Nome + telefone digitados no checkout | vêm do login (`/auth/me`) |
| Endereço em texto livre | `enderecoId` (cadastrado em `/enderecos`) |
| `window.confirm` + número `Date.now()` | `POST /pedidos/calcular` → revisão → `POST /pedidos` → `id` real |
| Volta ao cardápio após confirmar | tela de acompanhamento com `GET /pedidos/:id` |

Enquanto a API não existe, o `src/services/api.ts` do mobile pode devolver dados de teste **neste mesmo formato**.
