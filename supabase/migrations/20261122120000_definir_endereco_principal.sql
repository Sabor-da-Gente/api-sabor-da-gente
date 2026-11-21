begin;

create or replace function public.definir_endereco_principal(p_endereco_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'Entre na sua conta para alterar seus endereços.' using hint = 'NAO_AUTENTICADO';
  end if;

  perform 1 from public.perfis where id = v_uid for update;

  perform 1 from public.enderecos
   where id = p_endereco_id and usuario_id = v_uid and ativo;
  if not found then
    raise exception 'Endereço não encontrado.' using hint = 'NAO_ENCONTRADO';
  end if;

  update public.enderecos
     set principal = (id = p_endereco_id)
   where usuario_id = v_uid
     and (principal or id = p_endereco_id);

  return jsonb_build_object('id', p_endereco_id, 'principal', true);
end;
$$;

revoke execute on function public.definir_endereco_principal(bigint) from public, anon;
grant execute on function public.definir_endereco_principal(bigint) to authenticated;

commit;
