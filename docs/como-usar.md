# Como usar o banco — Sabor da Gente (Supabase)

Guia para quem desenvolve o **app mobile** (PDM) e o **painel web** (DAW III).
Substitui o antigo `api.md`: não há mais API própria; os dois apps falam
direto com o Supabase pela biblioteca **supabase-js**.

- Modelo e regras de negócio: [`modelo-de-dados.md`](modelo-de-dados.md)
- Fluxo entre os sistemas: [`fluxo-sistemas.png`](fluxo-sistemas.png)
- SQL de verdade: [`../supabase/migrations/`](../supabase/migrations/)

> **Regra de ouro:** o app nunca manda preço. Ele manda IDs e quantidades,
> e o banco calcula tudo (`calcular_pedido` / `criar_pedido`).

---

## 1. Convenções

| Assunto | Regra |
|---|---|
| Dinheiro | inteiro em **centavos** (`4500` = R$ 45,00) |
| Datas | `timestamptz` (chega como texto ISO: `"2026-10-16T13:00:00+00:00"`) |
| Nomes | tabelas e colunas em `snake_case`, iguais ao banco |
| IDs | `bigint` no catálogo e pedidos; `uuid` para usuários |
| Erros | `error.message` é para mostrar ao usuário; `error.hint` traz o código (abaixo) |

### Códigos de erro (`error.hint`)
| Código | Quando |
|---|---|
| `NAO_AUTENTICADO` | ação exige login |
| `SEM_PERMISSAO` | cliente tentando ação de admin |
| `VALIDACAO` | dado inválido (3 sabores na Grande, troco menor que o total…) |
| `INDISPONIVEL` | produto, sabor, tamanho ou adicional desativado |
| `NAO_ENCONTRADO` | pedido não existe ou não é do usuário |
| `TRANSICAO_INVALIDA` | mudança de status fora do fluxo |

Tentativas bloqueadas pelo RLS em `select` **não dão erro**: simplesmente
não retornam linhas. Em `insert`/`update` sem permissão, o erro vem com
`error.code = '42501'`.

---

## 2. Configuração

### Variáveis de ambiente
Valores em **Project Settings → API Keys** e **Data API** no painel do Supabase.
Use a **publishable key** (pública). **Nunca** coloque a *secret key* /
*service_role* em app ou painel: ela ignora todas as regras de segurança.

**Mobile (`.env`):**
```
EXPO_PUBLIC_SUPABASE_URL=https://<projeto>.supabase.co
EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

### Cliente no app mobile (Expo)
```bash
npx expo install @supabase/supabase-js react-native-url-polyfill
```
(O `expo-sqlite` já está instalado no app.)

```ts
// src/lib/supabase.ts
import 'react-native-url-polyfill/auto';
import 'expo-sqlite/localStorage/install';
import { createClient } from '@supabase/supabase-js';

export const supabase = createClient(
  process.env.EXPO_PUBLIC_SUPABASE_URL!,
  process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
  {
    auth: {
      storage: localStorage,   // sessão salva no aparelho
      autoRefreshToken: true,
      persistSession: true,
      detectSessionInUrl: false,
    },
  },
);
```

### Cliente no painel web
```bash
npm install @supabase/supabase-js
```
```ts
import { createClient } from '@supabase/supabase-js';
export const supabase = createClient(URL_DO_PROJETO, PUBLISHABLE_KEY);
```

---

## 3. Login (Supabase Auth)

### Cadastro de cliente
O perfil (`perfis`) é criado sozinho por um gatilho, com `tipo = 'cliente'`.
```ts
const { data, error } = await supabase.auth.signUp({
  email: 'ana@email.com',
  password: 'minhasenha',
  options: { data: { nome: 'Ana Souza', telefone: '83999990000' } },
});
```

### Login e perfil
```ts
await supabase.auth.signInWithPassword({ email, password });

const { data: { user } } = await supabase.auth.getUser();
const { data: perfil } = await supabase
  .from('perfis')
  .select('id, nome, telefone, tipo')
  .eq('id', user!.id)
  .single();

await supabase.auth.signOut();
```

### Painel: só admin entra
```ts
if (perfil?.tipo !== 'admin') {
  await supabase.auth.signOut();
  // mostrar "Acesso restrito à pizzaria"
}
```

### Criar o primeiro admin
1. Painel do Supabase → **Authentication → Users → Add user** (e-mail e senha).
2. **SQL Editor**:
   ```sql
   update public.perfis set tipo = 'admin'
    where id = (select id from auth.users where email = 'admin@sabordagente.com');
   ```
Ninguém consegue virar admin pelo app: a coluna `tipo` não pode ser alterada
por usuários.

### Perfil e endereços
```ts
await supabase.from('perfis').update({ nome, telefone }).eq('id', perfil.id);

const { data: enderecos } = await supabase
  .from('enderecos').select('*').eq('ativo', true).order('principal', { ascending: false });

await supabase.from('enderecos').insert({
  apelido: 'Casa', logradouro: 'Rua Solon de Lucena', numero: '120',
  complemento: 'Apto 2', bairro: 'Centro', cidade: 'Esperança', uf: 'PB',
});                                       // usuario_id é preenchido sozinho

await supabase.from('enderecos').update({ ativo: false }).eq('id', id);   // "apagar"
```

---

## 4. Cardápio (qualquer pessoa, com ou sem login)

O RLS já filtra só os itens ativos para clientes.

```ts
const { data: categorias } = await supabase
  .from('categorias').select('id, nome, slug, tipo, icone, ordem').order('ordem');

// Produtos de uma categoria (pelo slug)
const { data: produtos } = await supabase
  .from('produtos')
  .select('id, categoria_id, nome, descricao, ingredientes, imagem_url, preco, destaque, categorias!inner(slug)')
  .eq('categorias.slug', 'esfihas')
  .order('nome');

// Destaques da tela inicial
const { data: destaques } = await supabase
  .from('produtos').select('*').eq('destaque', true);

// Tudo para "Monte sua pizza"
const [tamanhos, massas, sabores, adicionais, config] = await Promise.all([
  supabase.from('tamanhos').select('*').order('ordem'),
  supabase.from('massas').select('*').order('id'),
  supabase.from('sabores').select('*, sabor_precos(tamanho_id, preco)').order('nome'),
  supabase.from('adicionais').select('*').order('nome'),
  supabase.from('configuracoes').select('chave, valor'),
]);
```

> **No app:** depois de buscar, salve no SQLite do celular (persistência
> local). Sem internet, mostre a cópia salva.

---

## 5. Pedido (cliente logado)

### Formato dos itens
O mesmo formato serve para `calcular_pedido` e `criar_pedido`:
```ts
const itens = [
  { tipo: 'pizza', tamanhoId: 2, massaId: 1, saborIds: [1, 3], adicionalIds: [1],
    quantidade: 1, observacao: 'Bem assada' },
  { tipo: 'produto', produtoId: 1, quantidade: 6 },
];
```

| Campo | Regra |
|---|---|
| `itens` | 1 a 30 itens |
| `quantidade` | 1 a 50 |
| pizza `saborIds` | de 1 até `tamanhos.max_sabores`, sem repetir, todos com preço no tamanho |
| pizza `massaId` | obrigatório |
| `observacao` do item | até 200 caracteres |

### Revisão (não grava nada)
```ts
const { data, error } = await supabase.rpc('calcular_pedido', {
  p_itens: itens,
  p_tipo_entrega: 'entrega',     // ou 'retirada'
  p_cupom: 'BEMVINDO10',         // opcional
});
// data = { itens: [...com descricao/precoUnitario/subtotal], subtotal: 8000,
//          desconto: 800, taxaEntrega: 500, total: 7700, avisos: ['Cupom BEMVINDO10 aplicado.'] }
```

### Confirmar
```ts
const { data: pedido, error } = await supabase.rpc('criar_pedido', {
  p_itens: itens,
  p_tipo_entrega: 'entrega',
  p_forma_pagamento: 'dinheiro',   // 'pix' | 'cartao' | 'dinheiro'
  p_endereco_id: 3,                // obrigatório se entrega (endereço do próprio cliente)
  p_troco_para: 10000,             // só em dinheiro; >= total
  p_cupom: null,
  p_observacao: 'Sem cebola',      // até 300 caracteres
});
// pedido = { id: 42, status: 'realizado', itens: [...], subtotal, desconto, taxaEntrega, total }
if (error) mostrarErro(error.message);   // ex.: "Item 1: escolha de 1 a 2 sabores para o tamanho Grande."
```
Depois do sucesso: limpar o carrinho do SQLite e abrir o acompanhamento.

### Histórico e detalhes
```ts
const { data: historico } = await supabase
  .from('pedidos')
  .select('id, status, tipo_entrega, total, criado_em')
  .order('criado_em', { ascending: false });       // só os do cliente (RLS)

const { data: detalhe } = await supabase
  .from('pedidos')
  .select(`*,
    itens_pedido(*, itens_pedido_sabores(*), itens_pedido_adicionais(*)),
    pagamentos(*),
    pedido_status_historico(status, criado_em)`)
  .eq('id', 42)
  .single();
```

### Cancelar (só enquanto "realizado")
```ts
await supabase.rpc('cancelar_pedido', { p_pedido_id: 42 });
```

### Acompanhar em tempo real
```ts
const canal = supabase
  .channel(`pedido-${id}`)
  .on('postgres_changes',
      { event: 'UPDATE', schema: 'public', table: 'pedidos', filter: `id=eq.${id}` },
      (msg) => atualizarStatus(msg.new.status))
  .subscribe();

// ao sair da tela
supabase.removeChannel(canal);
```

### Status
| Valor | Texto para exibir |
|---|---|
| `realizado` | Pedido realizado |
| `em_preparacao` | Em preparação |
| `saiu_para_entrega` | Saiu para entrega |
| `pronto_para_retirada` | Pronto para retirada |
| `entregue` | Entregue |
| `cancelado` | Cancelado |

---

## 6. Favoritos (fase 2)
```ts
await supabase.from('favoritos').insert({ produto_id: 1 });   // ou { sabor_id: 3 }
await supabase.from('favoritos').select('*, produtos(*), sabores(*)');
await supabase.from('favoritos').delete().eq('produto_id', 1);
```

---

## 7. Painel administrativo (usuário admin)

### Pedidos
```ts
// Lista (admin vê todos)
const { data } = await supabase
  .from('pedidos')
  .select('id, status, tipo_entrega, total, criado_em, perfis(nome, telefone)')
  .in('status', ['realizado', 'em_preparacao'])
  .order('criado_em');

// Pedidos novos chegando na hora
supabase.channel('painel-pedidos')
  .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'pedidos' },
      (msg) => adicionarNaLista(msg.new))
  .subscribe();

// Mudar status (o banco recusa transições fora do fluxo)
await supabase.rpc('alterar_status', { p_pedido_id: 42, p_status: 'em_preparacao' });

// Aprovar pagamento em dinheiro
await supabase.from('pagamentos').update({ status: 'aprovado' }).eq('pedido_id', 42);
```

Fluxo permitido:
```
realizado ──► em_preparacao ──► saiu_para_entrega ──► entregue      (entrega)
                       └──────► pronto_para_retirada ─► entregue    (retirada)
realizado / em_preparacao ──► cancelado
```

### Cardápio
```ts
await supabase.from('produtos').insert({ categoria_id: 3, nome: 'Suco de laranja', preco: 700 });
await supabase.from('produtos').update({ preco: 450 }).eq('id', 1);
await supabase.from('produtos').update({ ativo: false }).eq('id', 2);   // desativar (não apagar)

// Preços de um sabor por tamanho
await supabase.from('sabor_precos').upsert([
  { sabor_id: 1, tamanho_id: 1, preco: 3900 },
  { sabor_id: 1, tamanho_id: 2, preco: 4600 },
]);

// Configurações
await supabase.from('configuracoes').update({ valor: '600' }).eq('chave', 'taxa_entrega');
await supabase.from('configuracoes').update({ valor: 'media' }).eq('chave', 'regra_preco_pizza');
```
Não apaguem itens do catálogo: pedidos antigos apontam para eles. Desativem.

### Clientes e estatísticas
```ts
await supabase.from('perfis').select('id, nome, telefone, criado_em, pedidos(count)').eq('tipo', 'cliente');

const { data: est } = await supabase.rpc('estatisticas_vendas', { p_de: '2026-10-01', p_ate: '2026-10-31' });
// { pedidos, cancelados, faturamento, ticketMedio, porStatus, porDia, maisVendidos }
```

---

## 8. Resumo do que cada um pode fazer

| Ação | Visitante | Cliente | Admin |
|---|---|---|---|
| Ver cardápio ativo | ✅ | ✅ | ✅ (inclusive inativos) |
| Alterar cardápio, cupons, configurações | — | — | ✅ |
| Ver/alterar próprio perfil (nome, telefone) | — | ✅ | ✅ |
| Endereços e favoritos | — | ✅ próprios | ✅ ver todos os endereços |
| `calcular_pedido` / `criar_pedido` | — | ✅ | ✅ |
| Ver pedidos | — | ✅ próprios | ✅ todos |
| `cancelar_pedido` | — | ✅ próprio, se "realizado" | — |
| `alterar_status` / aprovar pagamento | — | — | ✅ |
| `estatisticas_vendas` | — | — | ✅ |

Tudo isso é garantido **pelo banco** (RLS + funções), não pelo app: mesmo
que alguém altere o código do app, não consegue burlar.
