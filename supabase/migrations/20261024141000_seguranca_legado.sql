-- =====================================================================
-- Sabor da Gente — segurança para o banco legado.
-- Substitui a 120100 neste projeto: NÃO revoga nada das 4 tabelas legadas
-- (categorias, produtos, pedidos, itens_pedido), que o painel Web usa como
-- "anon". Protege só as tabelas novas e cria eh_admin() e o trigger que
-- grava o histórico quando o status muda (inclusive via .update() do Web).
-- Aplicar logo depois da 120500 e da 135000.
-- =====================================================================
begin;

do $$
begin
  if to_regclass('public.perfis') is null
     or to_regclass('public.pagamentos') is null
     or to_regclass('public.pedido_status_historico') is null then
    raise exception 'Aplique antes a 20261016120500_adaptar_schema_existente.';
  end if;
end;
$$;

create or replace function public.eh_admin()
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

-- RLS nas tabelas novas
alter table public.perfis                  enable row level security;
alter table public.enderecos               enable row level security;
alter table public.tamanhos                enable row level security;
alter table public.massas                  enable row level security;
alter table public.sabores                 enable row level security;
alter table public.sabor_precos            enable row level security;
alter table public.adicionais              enable row level security;
alter table public.cupons                  enable row level security;
alter table public.configuracoes           enable row level security;
alter table public.itens_pedido_sabores    enable row level security;
alter table public.itens_pedido_adicionais enable row level security;
alter table public.pedido_status_historico enable row level security;
alter table public.pagamentos              enable row level security;
alter table public.favoritos               enable row level security;

-- Permissões explícitas, só nas tabelas novas
revoke all on public.perfis, public.enderecos, public.tamanhos, public.massas,
              public.sabores, public.sabor_precos, public.adicionais, public.cupons,
              public.configuracoes, public.itens_pedido_sabores,
              public.itens_pedido_adicionais, public.pedido_status_historico,
              public.pagamentos, public.favoritos
  from anon, authenticated;

grant select on public.tamanhos, public.massas, public.sabores, public.sabor_precos,
                public.adicionais, public.configuracoes
  to anon, authenticated;
grant insert, update, delete on public.tamanhos, public.massas, public.sabores,
                public.sabor_precos, public.adicionais, public.configuracoes, public.cupons
  to authenticated;
grant select on public.cupons to authenticated;
grant select on public.perfis to authenticated;
grant update (nome, telefone) on public.perfis to authenticated;
grant select, insert, update, delete on public.enderecos, public.favoritos to authenticated;
grant select on public.itens_pedido_sabores, public.itens_pedido_adicionais,
                public.pedido_status_historico, public.pagamentos
  to authenticated;
grant update (status) on public.pagamentos to authenticated;

-- Catálogo novo
drop policy if exists "publico le tamanhos ativos" on public.tamanhos;
create policy "publico le tamanhos ativos" on public.tamanhos
  for select to anon, authenticated using (ativo or (select public.eh_admin()));
drop policy if exists "admin gerencia tamanhos" on public.tamanhos;
create policy "admin gerencia tamanhos" on public.tamanhos
  for all to authenticated using ((select public.eh_admin())) with check ((select public.eh_admin()));

drop policy if exists "publico le massas ativas" on public.massas;
create policy "publico le massas ativas" on public.massas
  for select to anon, authenticated using (ativo or (select public.eh_admin()));
drop policy if exists "admin gerencia massas" on public.massas;
create policy "admin gerencia massas" on public.massas
  for all to authenticated using ((select public.eh_admin())) with check ((select public.eh_admin()));

drop policy if exists "publico le sabores ativos" on public.sabores;
create policy "publico le sabores ativos" on public.sabores
  for select to anon, authenticated using (ativo or (select public.eh_admin()));
drop policy if exists "admin gerencia sabores" on public.sabores;
create policy "admin gerencia sabores" on public.sabores
  for all to authenticated using ((select public.eh_admin())) with check ((select public.eh_admin()));

drop policy if exists "publico le precos" on public.sabor_precos;
create policy "publico le precos" on public.sabor_precos
  for select to anon, authenticated using (true);
drop policy if exists "admin gerencia precos" on public.sabor_precos;
create policy "admin gerencia precos" on public.sabor_precos
  for all to authenticated using ((select public.eh_admin())) with check ((select public.eh_admin()));

drop policy if exists "publico le adicionais ativos" on public.adicionais;
create policy "publico le adicionais ativos" on public.adicionais
  for select to anon, authenticated using (ativo or (select public.eh_admin()));
drop policy if exists "admin gerencia adicionais" on public.adicionais;
create policy "admin gerencia adicionais" on public.adicionais
  for all to authenticated using ((select public.eh_admin())) with check ((select public.eh_admin()));

drop policy if exists "publico le configuracoes" on public.configuracoes;
create policy "publico le configuracoes" on public.configuracoes
  for select to anon, authenticated using (true);
drop policy if exists "admin gerencia configuracoes" on public.configuracoes;
create policy "admin gerencia configuracoes" on public.configuracoes
  for all to authenticated using ((select public.eh_admin())) with check ((select public.eh_admin()));

drop policy if exists "admin gerencia cupons" on public.cupons;
create policy "admin gerencia cupons" on public.cupons
  for all to authenticated using ((select public.eh_admin())) with check ((select public.eh_admin()));

-- Perfis, endereços, favoritos
drop policy if exists "usuario le o proprio perfil" on public.perfis;
create policy "usuario le o proprio perfil" on public.perfis
  for select to authenticated using (id = (select auth.uid()) or (select public.eh_admin()));
drop policy if exists "usuario altera o proprio perfil" on public.perfis;
create policy "usuario altera o proprio perfil" on public.perfis
  for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

drop policy if exists "cliente gerencia os proprios enderecos" on public.enderecos;
create policy "cliente gerencia os proprios enderecos" on public.enderecos
  for all to authenticated
  using (usuario_id = (select auth.uid())) with check (usuario_id = (select auth.uid()));
drop policy if exists "admin le enderecos" on public.enderecos;
create policy "admin le enderecos" on public.enderecos
  for select to authenticated using ((select public.eh_admin()));

drop policy if exists "cliente gerencia os proprios favoritos" on public.favoritos;
create policy "cliente gerencia os proprios favoritos" on public.favoritos
  for all to authenticated
  using (usuario_id = (select auth.uid())) with check (usuario_id = (select auth.uid()));

-- Detalhes do pedido: dono ou admin
drop policy if exists "dono ou admin le sabores do item" on public.itens_pedido_sabores;
create policy "dono ou admin le sabores do item" on public.itens_pedido_sabores
  for select to authenticated
  using (exists (select 1 from public.itens_pedido i
                   join public.pedidos p on p.id = i.pedido_id
                  where i.id = item_id
                    and (p.cliente_id = (select auth.uid()) or (select public.eh_admin()))));

drop policy if exists "dono ou admin le adicionais do item" on public.itens_pedido_adicionais;
create policy "dono ou admin le adicionais do item" on public.itens_pedido_adicionais
  for select to authenticated
  using (exists (select 1 from public.itens_pedido i
                   join public.pedidos p on p.id = i.pedido_id
                  where i.id = item_id
                    and (p.cliente_id = (select auth.uid()) or (select public.eh_admin()))));

drop policy if exists "dono ou admin le historico" on public.pedido_status_historico;
create policy "dono ou admin le historico" on public.pedido_status_historico
  for select to authenticated
  using (exists (select 1 from public.pedidos p
                  where p.id = pedido_id
                    and (p.cliente_id = (select auth.uid()) or (select public.eh_admin()))));

drop policy if exists "dono ou admin le pagamento" on public.pagamentos;
create policy "dono ou admin le pagamento" on public.pagamentos
  for select to authenticated
  using (exists (select 1 from public.pedidos p
                  where p.id = pedido_id
                    and (p.cliente_id = (select auth.uid()) or (select public.eh_admin()))));
drop policy if exists "admin altera pagamento" on public.pagamentos;
create policy "admin altera pagamento" on public.pagamentos
  for update to authenticated using ((select public.eh_admin())) with check ((select public.eh_admin()));

-- Histórico de status: grava toda mudança de pedidos.status
-- (RPC alterar_status/cancelar_pedido e .update() direto do painel Web)
create or replace function public.registrar_historico_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.pedido_status_historico (pedido_id, status, alterado_por)
  select new.id, new.status, p.id
    from (select 1) x
    left join public.perfis p on p.id = (select auth.uid());
  return new;
end;
$$;

revoke execute on function public.registrar_historico_status() from public, anon, authenticated;

drop trigger if exists trg_pedidos_historico_status on public.pedidos;
create trigger trg_pedidos_historico_status
  after update of status on public.pedidos
  for each row
  when (old.status is distinct from new.status)
  execute function public.registrar_historico_status();

commit;
