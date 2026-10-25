# 🍕 Sabor da Gente — banco de dados (Supabase)

Banco central do sistema Sabor da Gente, compartilhado por:

| Repositório | Usa o banco para |
|---|---|
| `mobile-sabor-da-gente` (PDM) | login, perfil, endereços, criar e acompanhar pedidos |
| `sabor--da-gente-web` (DAW III) | cardápio (produtos), pedidos e status |

Não há backend próprio: o app e o painel falam direto com o **Supabase**
(PostgreSQL + Auth + API automática + Realtime). As regras de negócio ficam em
**funções SQL**, e o preço de um pedido é sempre calculado no banco, nunca pelo app.

![Fluxo entre os sistemas](docs/fluxo-sistemas.png)

## Por que Supabase

- PostgreSQL na nuvem, gratuito, com autenticação pronta e API gerada automaticamente.
- Permite que o app (React Native) e o painel (Next.js) usem o mesmo banco sem escrever um servidor.
- Regras de negócio em SQL garantem que o preço do pedido não depende do app.

## Estado real do banco

O banco já existia (tabelas legadas `categorias`, `produtos`, `pedidos` e `itens_pedido`, com `pedidos.id` em UUID).
As migrations novas **adaptam** esse banco sem apagar nada. Por isso a ordem e a lista abaixo são específicas dele.

### Migrations aplicadas (nesta ordem, uma por vez no SQL Editor)

| # | Arquivo | O que faz |
|---|---|---|
| 1 | `20261016120500_adaptar_schema_existente.sql` | cria perfis, endereços, catálogo de pizza, pagamentos e histórico; acrescenta colunas às tabelas legadas |
| 2 | `20261024135000_funcoes_base.sql` | gatilhos de `atualizado_em` e criação automática do perfil no cadastro |
| 3 | `20261024141000_seguranca_legado.sql` | `eh_admin()`, RLS nas tabelas novas e gatilho que grava o histórico de status |
| 4 | `20261016120200_funcoes.sql` | funções originais de cálculo e de pedido |
| 5 | `20261024140000_corrigir_funcoes_pedidos.sql` | corrige `criar_pedido`, `alterar_status` e `cancelar_pedido` para UUID e para o schema legado |
| 6 | `20261024142000_catalogo_novo.sql` | tamanhos, massas, sabores, preços, adicionais, cupom e taxa de entrega |
| 7 | `20261024143000_realtime_legado.sql` | avisos em tempo real |
| 8 | `20261024150000_status_pronto_retirada.sql` | status `pronto_para_retirada` |

### ⚠️ Migrations que NÃO devem ser aplicadas neste banco

`20261016120000_tabelas.sql`, `20261016120100_seguranca_rls.sql`, `20261016120300_realtime.sql`
e `20261016120400_cardapio_inicial.sql` pertencem ao desenho original (banco novo) e **conflitam** com o banco legado.
Por isso também **não use `supabase db push`** neste projeto: aplique pelo SQL Editor, na ordem da tabela.

## Status do pedido

`recebido` → `em_preparo` → `saiu_para_entrega` → `entregue` (entrega)
`recebido` → `em_preparo` → `pronto_para_retirada` → `entregue` (retirada)
`recebido` ou `em_preparo` → `cancelado`

O histórico de cada mudança é gravado por um gatilho, inclusive quando o painel altera o status direto na tabela.

## Funções principais

| Função | Quem chama | O que faz |
|---|---|---|
| `calcular_pedido(itens, tipo_entrega, cupom)` | app | simula o total sem gravar |
| `criar_pedido(...)` | app (logado) | valida, recalcula preços no banco e grava pedido, itens, pagamento e histórico |
| `cancelar_pedido(id)` | app (dono do pedido) | cancela enquanto o status é `recebido` |
| `alterar_status(id, status)` | admin | muda o status respeitando as transições |
| `estatisticas_vendas(de, ate)` | admin | faturamento, ticket médio e mais vendidos |

## Como usar o banco

1. A URL e a *publishable key* do projeto já estão no `.env` do app e do painel.
2. Para criar um administrador: **Authentication → Users → Add user** e, no SQL Editor:

        update public.perfis set tipo = 'admin'
         where id = (select id from auth.users where email = 'EMAIL_DO_ADMIN');

3. Detalhes de uso do `supabase-js` em [`docs/como-usar.md`](docs/como-usar.md) e das tabelas em [`docs/modelo-de-dados.md`](docs/modelo-de-dados.md).

> ⚠️ Nunca use a *secret key* / *service_role* no app ou no painel: ela ignora todas as regras de segurança.
> Este projeto é acadêmico: as tabelas legadas continuam com acesso aberto à chave pública para o painel funcionar sem login.

## Estrutura

    supabase/migrations/   SQL do banco
    docs/                  modelo de dados, guia de uso e diagramas
    backup-migrations/     (só local, fora do Git) cópias de segurança


## Regras da equipe

- **Toda mudança no banco é uma nova migration** (`npx supabase migration new nome`).
  Não editem migrations já aplicadas e não mudem tabelas direto pelo painel
  sem registrar aqui — senão os bancos de cada um ficam diferentes.
- Toda tabela nova precisa de **RLS + permissões** (ver `…_seguranca_rls.sql`).
- O app nunca manda preço: pedidos só pelas funções `calcular_pedido` / `criar_pedido`.
- Mudou alguma tabela ou função usada pelos apps? Atualize `docs/como-usar.md`
  e avise nos repositórios do app e do painel.

## Testes (opcional)

Os testes rodam as migrations num PostgreSQL local que imita o Supabase e
conferem as regras como visitante, cliente e admin (59 verificações).

```bash
PGHOST=localhost PGUSER=postgres ./testes/recriar_banco.sh
pip install "psycopg[binary]"
TESTE_DSN="host=localhost user=postgres dbname=sabor_teste" python3 testes/testar_regras.py
```

## Plano gratuito do Supabase

- O projeto é **pausado após 7 dias sem uso** — reative pelo painel antes de apresentar.
- 500 MB de banco e 2 projetos por organização (de sobra para o projeto).
