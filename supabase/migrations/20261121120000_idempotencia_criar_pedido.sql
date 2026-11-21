begin;

alter table public.pedidos add column if not exists chave_cliente uuid;

comment on column public.pedidos.chave_cliente is
  'UUID gerado pelo app por pedido, para não duplicar em reenvios. Nulo em pedidos antigos e do painel.';

create unique index if not exists uq_pedidos_cliente_chave
  on public.pedidos (cliente_id, chave_cliente);

drop function if exists public.criar_pedido(jsonb, text, text, bigint, integer, text, text);

create function public.criar_pedido(
  p_itens           jsonb,
  p_tipo_entrega    text,
  p_forma_pagamento text,
  p_endereco_id     bigint  default null,
  p_troco_para      integer default null,
  p_cupom           text    default null,
  p_observacao      text    default null,
  p_chave_cliente   uuid    default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid         uuid := (select auth.uid());
  v_perfil      record;
  v_end         record;
  v_end_texto   text;
  v_itens       jsonb;
  v_totais      jsonb;
  v_total       integer;
  v_pedido_id   uuid;
  v_numero      bigint;
  v_item_id     bigint;
  v_item        jsonb;
  v_sub         jsonb;
  v_nome_item   text;
  v_adic_txt    text;
  v_sabores_txt text[];
  v_existente   record;
  v_restricao   text;
begin
  if v_uid is null then
    raise exception 'Entre na sua conta para fazer o pedido.' using hint = 'NAO_AUTENTICADO';
  end if;

  
  if p_chave_cliente is not null then
    select id, numero, status, subtotal, desconto, taxa_entrega, total into v_existente
      from public.pedidos
     where cliente_id = v_uid and chave_cliente = p_chave_cliente;
    if found then
      return jsonb_build_object('id', v_existente.id, 'numero', v_existente.numero,
                                'status', v_existente.status, 'subtotal', v_existente.subtotal,
                                'desconto', v_existente.desconto, 'taxaEntrega', v_existente.taxa_entrega,
                                'total', v_existente.total, 'repetido', true);
    end if;
  end if;
  if p_tipo_entrega not in ('entrega', 'retirada') then
    raise exception 'Escolha entrega ou retirada.' using hint = 'VALIDACAO';
  end if;
  if p_forma_pagamento not in ('pix', 'cartao', 'dinheiro') then
    raise exception 'Forma de pagamento deve ser pix, cartao ou dinheiro.' using hint = 'VALIDACAO';
  end if;
  if length(p_observacao) > 300 then
    raise exception 'A observação do pedido pode ter até 300 caracteres.' using hint = 'VALIDACAO';
  end if;

  select nome, telefone into v_perfil from public.perfis where id = v_uid;
  if not found or nullif(btrim(v_perfil.nome), '') is null then
    raise exception 'Complete seu cadastro (nome) para fazer o pedido.' using hint = 'VALIDACAO';
  end if;
  if nullif(btrim(v_perfil.telefone), '') is null then
    raise exception 'Cadastre seu telefone no perfil para fazer o pedido.' using hint = 'VALIDACAO';
  end if;

  if p_tipo_entrega = 'entrega' then
    select * into v_end from public.enderecos
     where id = p_endereco_id and usuario_id = v_uid and ativo;
    if not found then
      raise exception 'Escolha um endereço de entrega válido.' using hint = 'VALIDACAO';
    end if;
    v_end_texto := format('%s, %s%s — %s, %s/%s',
      v_end.logradouro, v_end.numero,
      coalesce(', ' || nullif(v_end.complemento, ''), ''),
      v_end.bairro, v_end.cidade, v_end.uf);
  end if;

  v_itens  := public.calcular_itens(p_itens);
  v_totais := public.calcular_totais(v_itens, p_tipo_entrega, p_cupom);
  v_total  := (v_totais ->> 'total')::integer;

  if p_troco_para is not null then
    if p_forma_pagamento <> 'dinheiro' then
      raise exception 'Troco só vale para pagamento em dinheiro.' using hint = 'VALIDACAO';
    end if;
    if p_troco_para < v_total then
      raise exception 'O troco deve ser para um valor maior ou igual ao total.' using hint = 'VALIDACAO';
    end if;
  end if;

  begin
    insert into public.pedidos (cliente_id, cliente_nome, cliente_telefone,
                                tipo_entrega, endereco_id, endereco_entrega,
                                forma_pagamento, troco_para, observacao,
                                cupom_id, subtotal, desconto, taxa_entrega, total, status,
                                chave_cliente)
    values (v_uid, btrim(v_perfil.nome), btrim(v_perfil.telefone),
            p_tipo_entrega,
            case when p_tipo_entrega = 'entrega' then p_endereco_id end,
            v_end_texto,
            p_forma_pagamento, p_troco_para,
            nullif(btrim(p_observacao), ''),
            (v_totais ->> 'cupomId')::bigint,
            (v_totais ->> 'subtotal')::integer,
            (v_totais ->> 'desconto')::integer,
            (v_totais ->> 'taxaEntrega')::integer,
            v_total,
            'recebido',
            p_chave_cliente)
    returning id, numero into v_pedido_id, v_numero;
  exception when unique_violation then
    
    get stacked diagnostics v_restricao = constraint_name;
    if v_restricao is distinct from 'uq_pedidos_cliente_chave' then
      raise;
    end if;
    select id, numero, status, subtotal, desconto, taxa_entrega, total into v_existente
      from public.pedidos
     where cliente_id = v_uid and chave_cliente = p_chave_cliente;
    return jsonb_build_object('id', v_existente.id, 'numero', v_existente.numero,
                              'status', v_existente.status, 'subtotal', v_existente.subtotal,
                              'desconto', v_existente.desconto, 'taxaEntrega', v_existente.taxa_entrega,
                              'total', v_existente.total, 'repetido', true);
  end;

  for v_item in select value from jsonb_array_elements(v_itens) loop
  
    v_nome_item := case when v_item ->> 'tipo' = 'pizza'
                        then format('Pizza %s (%s)', v_item -> 'tamanho' ->> 'nome', v_item -> 'massa' ->> 'nome')
                        else v_item ->> 'descricao' end;

    select string_agg(a ->> 'nome', ', ') into v_adic_txt
      from jsonb_array_elements(coalesce(v_item -> 'adicionais', '[]'::jsonb)) a;
    if v_adic_txt is not null then
      v_nome_item := v_nome_item || ' + ' || v_adic_txt;
    end if;

    v_sabores_txt := array(
      select s ->> 'nome'
        from jsonb_array_elements(coalesce(v_item -> 'sabores', '[]'::jsonb)) with ordinality as t(s, ord)
       order by ord);

    insert into public.itens_pedido (pedido_id, nome, sabores, quantidade, preco_unitario,
                                     tipo, produto_id, tamanho_id, massa_id, descricao,
                                     subtotal, observacao)
    values (v_pedido_id,
            v_nome_item,
            v_sabores_txt,
            (v_item ->> 'quantidade')::integer,
            (v_item ->> 'precoUnitario')::integer,
            v_item ->> 'tipo',
            (v_item ->> 'produtoId')::bigint,
            (v_item -> 'tamanho' ->> 'id')::bigint,
            (v_item -> 'massa' ->> 'id')::bigint,
            v_item ->> 'descricao',
            (v_item ->> 'subtotal')::integer,
            v_item ->> 'observacao')
    returning id into v_item_id;

    for v_sub in select value from jsonb_array_elements(coalesce(v_item -> 'sabores', '[]'::jsonb)) loop
      insert into public.itens_pedido_sabores (item_id, sabor_id, nome, preco)
      values (v_item_id, (v_sub ->> 'id')::bigint, v_sub ->> 'nome', (v_sub ->> 'preco')::integer);
    end loop;

    for v_sub in select value from jsonb_array_elements(coalesce(v_item -> 'adicionais', '[]'::jsonb)) loop
      insert into public.itens_pedido_adicionais (item_id, adicional_id, nome, preco)
      values (v_item_id, (v_sub ->> 'id')::bigint, v_sub ->> 'nome', (v_sub ->> 'preco')::integer);
    end loop;
  end loop;

  insert into public.pagamentos (pedido_id, forma, status, valor, troco_para)
  values (v_pedido_id, p_forma_pagamento,
          case when p_forma_pagamento = 'dinheiro' then 'pendente' else 'aprovado' end,
          v_total, p_troco_para);

  insert into public.pedido_status_historico (pedido_id, status, alterado_por)
  values (v_pedido_id, 'recebido', v_uid);

  return jsonb_build_object('id', v_pedido_id, 'numero', v_numero,
                            'status', 'recebido', 'itens', v_itens, 'repetido', false)
         || (v_totais - 'cupomId');
end;
$$;

revoke execute on function public.criar_pedido(jsonb, text, text, bigint, integer, text, text, uuid) from public, anon;
grant execute on function public.criar_pedido(jsonb, text, text, bigint, integer, text, text, uuid) to authenticated;

commit;
