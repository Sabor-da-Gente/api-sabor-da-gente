-- =====================================================================
-- Sabor da Gente — 2/5: segurança (permissões + Row Level Security)
--
-- O app e o painel falam direto com o banco usando a chave pública do
-- projeto. Por isso TODA tabela tem RLS ligado e permissões explícitas:
--
--   anon          = visitante sem login   → só lê o cardápio
--   authenticated = cliente ou admin      → regras abaixo
--
-- Pedidos, itens, pagamentos e histórico NUNCA são gravados direto:
-- só pelas funções criar_pedido / alterar_status / cancelar_pedido
-- (3/5), que validam tudo e recalculam os preços.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Quem é admin? (usada nas regras abaixo)
-- security definer: consulta perfis sem cair nas regras de perfis.
-- ---------------------------------------------------------------------
create function public.eh_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.perfis
     where id = (select auth.uid()) and tipo = 'admin'
  );
$$;

revoke execute on function public.eh_admin() from public;
grant execute on function public.eh_admin() to anon, authenticated;

-- ---------------------------------------------------------------------
-- Liga o RLS em todas as tabelas
-- ---------------------------------------------------------------------
alter table public.perfis                  enable row level security;
alter table public.enderecos               enable row level security;
alter table public.categorias              enable row level security;
alter table public.produtos                enable row level security;
alter table public.tamanhos                enable row level security;
alter table public.massas                  enable row level security;
alter table public.sabores                 enable row level security;
alter table public.sabor_precos            enable row level security;
alter table public.adicionais              enable row level security;
alter table public.cupons                  enable row level security;
alter table public.configuracoes           enable row level security;
alter table public.pedidos                 enable row level security;
alter table public.itens_pedido            enable row level security;
alter table public.itens_pedido_sabores    enable row level security;
alter table public.itens_pedido_adicionais enable row level security;
alter table public.pedido_status_historico enable row level security;
alter table public.pagamentos              enable row level security;
alter table public.favoritos               enable row level security;

-- ---------------------------------------------------------------------
-- Permissões explícitas (não dependem dos padrões do projeto)
-- ---------------------------------------------------------------------
revoke all on all tables in schema public from anon, authenticated;

-- Catálogo: todos leem; só admin altera (as regras abaixo restringem)
grant select on public.categorias, public.produtos, public.tamanhos, public.massas,
                public.sabores, public.sabor_precos, public.adicionais, public.configuracoes
  to anon, authenticated;
grant insert, update, delete on public.categorias, public.produtos, public.tamanhos,
                public.massas, public.sabores, public.sabor_precos, public.adicionais,
                public.configuracoes, public.cupons
  to authenticated;
grant select on public.cupons to authenticated;

-- Perfil: lê o próprio; altera só nome e telefone (nunca o tipo!)
grant select on public.perfis to authenticated;
grant update (nome, telefone) on public.perfis to authenticated;

-- Endereços e favoritos: o cliente gerencia os próprios
grant select, insert, update, delete on public.enderecos, public.favoritos to authenticated;

-- Pedidos: só leitura (gravação pelas funções)
grant select on public.pedidos, public.itens_pedido, public.itens_pedido_sabores,
                public.itens_pedido_adicionais, public.pedido_status_historico,
                public.pagamentos
  to authenticated;
-- Admin pode marcar o pagamento como aprovado/recusado
grant update (status) on public.pagamentos to authenticated;

-- ---------------------------------------------------------------------
-- Regras (policies)
-- ---------------------------------------------------------------------

-- Catálogo: público vê o que está ativo; admin vê e gerencia tudo
create policy "publico le categorias ativas" on public.categorias
  for select to anon, authenticated using (ativa or (select public.eh_admin()));
create policy "admin gerencia categorias" on public.categorias
  for all to authenticated using ((select public.eh_admin())) with check ((select public.eh_admin()));

create policy "publico le produtos ativos" on public.produtos
  for select to anon, authenticated using (ativo or (select public.eh_admin()));
create policy "admin gerencia produtos" on public.produtos
  for all to authenticated using ((select public.eh_admin())) with check ((select public.eh_admin()));

create policy "publico le tamanhos ativos" on public.tamanhos
  for select to anon, authenticated using (ativo or (select public.eh_admin()));
create policy "admin gerencia tamanhos" on public.tamanhos
  for all to authenticated using ((select public.eh_admin())) with check ((select public.eh_admin()));

create policy "publico le massas ativas" on public.massas
  for select to anon, authenticated using (ativo or (select public.eh_admin()));
create policy "admin gerencia massas" on public.massas
  for all to authenticated using ((select public.eh_admin())) with check ((select public.eh_admin()));

create policy "publico le sabores ativos" on public.sabores
  for select to anon, authenticated using (ativo or (select public.eh_admin()));
create policy "admin gerencia sabores" on public.sabores
  for all to authenticated using ((select public.eh_admin())) with check ((select public.eh_admin()));

create policy "publico le precos" on public.sabor_precos
  for select to anon, authenticated using (true);
create policy "admin gerencia precos" on public.sabor_precos
  for all to authenticated using ((select public.eh_admin())) with check ((select public.eh_admin()));

create policy "publico le adicionais ativos" on public.adicionais
  for select to anon, authenticated using (ativo or (select public.eh_admin()));
create policy "admin gerencia adicionais" on public.adicionais
  for all to authenticated using ((select public.eh_admin())) with check ((select public.eh_admin()));

create policy "publico le configuracoes" on public.configuracoes
  for select to anon, authenticated using (true);
create policy "admin gerencia configuracoes" on public.configuracoes
  for all to authenticated using ((select public.eh_admin())) with check ((select public.eh_admin()));

-- Cupons: só admin vê a tabela (o cliente valida pela função calcular_pedido)
create policy "admin gerencia cupons" on public.cupons
  for all to authenticated using ((select public.eh_admin())) with check ((select public.eh_admin()));

-- Perfis
create policy "usuario le o proprio perfil" on public.perfis
  for select to authenticated using (id = (select auth.uid()) or (select public.eh_admin()));
create policy "usuario altera o proprio perfil" on public.perfis
  for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- Endereços
create policy "cliente gerencia os proprios enderecos" on public.enderecos
  for all to authenticated
  using (usuario_id = (select auth.uid()))
  with check (usuario_id = (select auth.uid()));
create policy "admin le enderecos" on public.enderecos
  for select to authenticated using ((select public.eh_admin()));

-- Favoritos
create policy "cliente gerencia os proprios favoritos" on public.favoritos
  for all to authenticated
  using (usuario_id = (select auth.uid()))
  with check (usuario_id = (select auth.uid()));

-- Pedidos e tudo que pende deles: dono ou admin
create policy "dono ou admin le pedidos" on public.pedidos
  for select to authenticated
  using (cliente_id = (select auth.uid()) or (select public.eh_admin()));

create policy "dono ou admin le itens" on public.itens_pedido
  for select to authenticated
  using (exists (select 1 from public.pedidos p
                  where p.id = pedido_id
                    and (p.cliente_id = (select auth.uid()) or (select public.eh_admin()))));

create policy "dono ou admin le sabores do item" on public.itens_pedido_sabores
  for select to authenticated
  using (exists (select 1 from public.itens_pedido i
                   join public.pedidos p on p.id = i.pedido_id
                  where i.id = item_id
                    and (p.cliente_id = (select auth.uid()) or (select public.eh_admin()))));

create policy "dono ou admin le adicionais do item" on public.itens_pedido_adicionais
  for select to authenticated
  using (exists (select 1 from public.itens_pedido i
                   join public.pedidos p on p.id = i.pedido_id
                  where i.id = item_id
                    and (p.cliente_id = (select auth.uid()) or (select public.eh_admin()))));

create policy "dono ou admin le historico" on public.pedido_status_historico
  for select to authenticated
  using (exists (select 1 from public.pedidos p
                  where p.id = pedido_id
                    and (p.cliente_id = (select auth.uid()) or (select public.eh_admin()))));

create policy "dono ou admin le pagamento" on public.pagamentos
  for select to authenticated
  using (exists (select 1 from public.pedidos p
                  where p.id = pedido_id
                    and (p.cliente_id = (select auth.uid()) or (select public.eh_admin()))));
create policy "admin altera pagamento" on public.pagamentos
  for update to authenticated using ((select public.eh_admin())) with check ((select public.eh_admin()));
