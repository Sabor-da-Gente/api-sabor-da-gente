-- =====================================================================
-- Sabor da Gente — funções base que a 120500 (adaptar) não cria:
-- tocar_atualizado_em, criar_perfil_novo_usuario e seus triggers.
-- Aplicar DEPOIS de 20261016120500 e ANTES de 20261016120200.
-- =====================================================================
begin;

do $$
declare v_falta text[] := '{}'; r record;
begin
  for r in select * from (values
    ('perfis','atualizado_em'), ('perfis','tipo'), ('perfis','telefone'),
    ('produtos','atualizado_em'), ('pedidos','atualizado_em')
  ) as t(tabela, coluna)
  loop
    if not exists (select 1 from information_schema.columns c
                    where c.table_schema = 'public'
                      and c.table_name = r.tabela and c.column_name = r.coluna) then
      v_falta := v_falta || (r.tabela || '.' || r.coluna);
    end if;
  end loop;
  if cardinality(v_falta) > 0 then
    raise exception 'Aplique antes a 20261016120500_adaptar_schema_existente. Faltando: %',
      array_to_string(v_falta, ', ');
  end if;
end;
$$;

create or replace function public.tocar_atualizado_em()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.atualizado_em := now();
  return new;
end;
$$;

drop trigger if exists trg_perfis_atualizado on public.perfis;
create trigger trg_perfis_atualizado before update on public.perfis
  for each row execute function public.tocar_atualizado_em();

drop trigger if exists trg_produtos_atualizado on public.produtos;
create trigger trg_produtos_atualizado before update on public.produtos
  for each row execute function public.tocar_atualizado_em();

drop trigger if exists trg_pedidos_atualizado on public.pedidos;
create trigger trg_pedidos_atualizado before update on public.pedidos
  for each row execute function public.tocar_atualizado_em();

-- Cria o perfil quando alguém se cadastra (app manda nome/telefone em options.data)
create or replace function public.criar_perfil_novo_usuario()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.perfis (id, nome, telefone)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'nome', ''),
             nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
             'Cliente'),
    nullif(new.raw_user_meta_data ->> 'telefone', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists trg_auth_novo_usuario on auth.users;
create trigger trg_auth_novo_usuario after insert on auth.users
  for each row execute function public.criar_perfil_novo_usuario();

-- Usuários que já existem no Auth ganham perfil (tipo 'cliente'; admin é promovido à mão)
insert into public.perfis (id, nome, telefone)
select u.id,
       coalesce(nullif(u.raw_user_meta_data ->> 'nome', ''),
                nullif(split_part(coalesce(u.email, ''), '@', 1), ''),
                'Cliente'),
       nullif(u.raw_user_meta_data ->> 'telefone', '')
  from auth.users u
on conflict (id) do nothing;

commit;
