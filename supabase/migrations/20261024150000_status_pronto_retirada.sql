-- =====================================================================
-- Sabor da Gente — adiciona o status "pronto_para_retirada" (usado pelo Mobile)
-- Retirada: recebido -> em_preparo -> pronto_para_retirada -> entregue
-- Entrega:  recebido -> em_preparo -> saiu_para_entrega -> entregue
-- O histórico continua sendo gravado pelo trigger trg_pedidos_historico_status.
-- =====================================================================
begin;

do $$
declare
  r record;
  v_qtd integer := 0;
begin
  for r in
    select conname from pg_constraint
     where conrelid = 'public.pedidos'::regclass and contype = 'c'
       and pg_get_constraintdef(oid) like '%status%'
  loop
    execute format('alter table public.pedidos drop constraint %I', r.conname);
    v_qtd := v_qtd + 1;
  end loop;
  if v_qtd <> 1 then
    raise exception 'Esperava 1 CHECK de status em pedidos, encontrei %. Nada foi alterado.', v_qtd;
  end if;
end;
$$;

alter table public.pedidos
  add constraint pedidos_status_check
  check (status in ('recebido', 'em_preparo', 'saiu_para_entrega',
                    'pronto_para_retirada', 'entregue', 'cancelado'));

create or replace function public.alterar_status(p_pedido_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pedido   record;
  v_validos  text[];
begin
  if not public.eh_admin() then
    raise exception 'Apenas a pizzaria pode alterar o status do pedido.' using hint = 'SEM_PERMISSAO';
  end if;

  select id, status, tipo_entrega into v_pedido
    from public.pedidos where id = p_pedido_id for update;
  if not found then
    raise exception 'Pedido % não encontrado.', p_pedido_id using hint = 'NAO_ENCONTRADO';
  end if;

  v_validos := case v_pedido.status
    when 'recebido'             then array['em_preparo', 'cancelado']
    when 'em_preparo'           then case v_pedido.tipo_entrega
                                       when 'entrega' then array['saiu_para_entrega', 'cancelado']
                                       else array['pronto_para_retirada', 'cancelado'] end
    when 'saiu_para_entrega'    then array['entregue']
    when 'pronto_para_retirada' then array['entregue']
    else array[]::text[]
  end;

  if not (p_status = any (v_validos)) then
    raise exception 'Não é possível mudar de "%" para "%".', v_pedido.status, p_status
      using hint = 'TRANSICAO_INVALIDA';
  end if;

  -- o histórico é gravado pelo trigger trg_pedidos_historico_status
  update public.pedidos set status = p_status where id = p_pedido_id;

  return jsonb_build_object('id', p_pedido_id, 'status', p_status, 'statusAnterior', v_pedido.status);
end;
$$;

commit;
