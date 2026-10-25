-- =====================================================================
-- Sabor da Gente — correção das funções de pedidos (UUID + schema legado)
--
-- Corrige em relação a 20261016120200_funcoes.sql:
--  * pedidos.id é UUID (era bigint em criar_pedido/alterar_status/cancelar_pedido)
--  * INSERT em pedidos preenche os campos legados (cliente_nome, cliente_telefone,
--    forma_pagamento, troco_para); "numero" é IDENTITY e é gerado pelo banco
--  * INSERT em itens_pedido preenche nome e sabores (legados); id é IDENTITY
--  * status alinhados ao painel Web:
--    recebido, em_preparo, saiu_para_entrega, entregue, cancelado
--  * cancelar_pedido não deixa cancelar pedido legado sem cliente_id
-- As funções de cálculo e estatisticas_vendas NÃO são alteradas.
-- =====================================================================
begin;

-- ---------------------------------------------------------------------
-- 0) Pré-requisitos: aborta com mensagem clara se o schema não estiver pronto
-- ---------------------------------------------------------------------
do $$
declare
  v_falta text[] := '{}';
  r record;
begin
  for r in
    select * from (values
      ('pedidos',                     'id',            'uuid'),
      ('pedidos',                     'cliente_id',    'uuid'),
      ('pedidos',                     'endereco_id',   null),
      ('pedidos',                     'observacao',    null),
      ('pedidos',                     'cupom_id',      null),
      ('pedidos',                     'subtotal',      null),
      ('pedidos',                     'desconto',      null),
      ('pedidos',                     'taxa_entrega',  null),
      ('itens_pedido',                'pedido_id',     'uuid'),
      ('itens_pedido',                'tipo',          null),
      ('itens_pedido',                'produto_id',    null),
      ('itens_pedido',                'tamanho_id',    null),
      ('itens_pedido',                'massa_id',      null),
      ('itens_pedido',                'descricao',     null),
      ('itens_pedido',                'subtotal',      null),
      ('itens_pedido',                'observacao',    null),
      ('itens_pedido_sabores',        'item_id',       null),
      ('itens_pedido_sabores',        'sabor_id',      null),
      ('itens_pedido_sabores',        'nome',          null),
      ('itens_pedido_sabores',        'preco',         null),
      ('itens_pedido_adicionais',     'item_id',       null),
      ('itens_pedido_adicionais',     'adicional_id',  null),
      ('itens_pedido_adicionais',     'nome',          null),
      ('itens_pedido_adicionais',     'preco',         null),
      ('pagamentos',                  'pedido_id',     'uuid'),
      ('pagamentos',                  'forma',         null),
      ('pagamentos',                  'status',        null),
      ('pagamentos',                  'valor',         null),
      ('pagamentos',                  'troco_para',    null),
      ('pedido_status_historico',     'pedido_id',     'uuid'),
      ('pedido_status_historico',     'status',        null),
      ('pedido_status_historico',     'alterado_por',  null),
      ('perfis',                      'id',            'uuid'),
      ('perfis',                      'nome',          null),
      ('perfis',                      'telefone',      null),
      ('enderecos',                   'usuario_id',    'uuid'),
      ('enderecos',                   'ativo',         null)
    ) as t(tabela, coluna, tipo)
  loop
    if not exists (
      select 1 from information_schema.columns c
       where c.table_schema = 'public'
         and c.table_name = r.tabela
         and c.column_name = r.coluna
         and (r.tipo is null or c.udt_name = r.tipo)
    ) then
      v_falta := v_falta || format('%s.%s%s', r.tabela, r.coluna,
                                   coalesce(' (esperado ' || r.tipo || ')', ''));
    end if;
  end loop;

  for r in
    select unnest(array[
      'public.eh_admin()',
      'public.calcular_itens(jsonb)',
      'public.calcular_totais(jsonb,text,text)',
      'public.calcular_pedido(jsonb,text,text)'
    ]) as f
  loop
    if to_regprocedure(r.f) is null then
      v_falta := v_falta || ('função ' || r.f);
    end if;
  end loop;

  -- CHECKs de status precisam aceitar os 5 status do Web
  if exists (
    select 1 from pg_constraint
     where conrelid = to_regclass('public.pedidos') and contype = 'c'
       and pg_get_constraintdef(oid) like '%status%'
       and not (pg_get_constraintdef(oid) like '%recebido%'
            and pg_get_constraintdef(oid) like '%em_preparo%'
            and pg_get_constraintdef(oid) like '%saiu_para_entrega%'
            and pg_get_constraintdef(oid) like '%entregue%'
            and pg_get_constraintdef(oid) like '%cancelado%')
  ) then
    v_falta := v_falta || 'CHECK de pedidos.status não aceita os 5 status do Web';
  end if;

  if exists (
    select 1 from pg_constraint
     where conrelid = to_regclass('public.pedido_status_historico') and contype = 'c'
       and pg_get_constraintdef(oid) like '%status%'
       and not (pg_get_constraintdef(oid) like '%recebido%'
            and pg_get_constraintdef(oid) like '%em_preparo%'
            and pg_get_constraintdef(oid) like '%saiu_para_entrega%'
            and pg_get_constraintdef(oid) like '%entregue%'
            and pg_get_constraintdef(oid) like '%cancelado%')
  ) then
    v_falta := v_falta || 'CHECK de pedido_status_historico.status não aceita os 5 status do Web';
  end if;

  if cardinality(v_falta) > 0 then
    raise exception 'Migration abortada. Pré-requisitos ausentes: %', array_to_string(v_falta, '; ');
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 1) Remove as assinaturas antigas (bigint). Sem CASCADE de propósito:
--    se algo depender delas, a migration falha em vez de apagar o dependente.
-- ---------------------------------------------------------------------
drop function if exists public.alterar_status(bigint, text);
drop function if exists public.cancelar_pedido(bigint);

-- ---------------------------------------------------------------------
-- 2) criar_pedido (mesma assinatura; id do pedido agora é UUID)
-- ---------------------------------------------------------------------
create or replace function public.criar_pedido(
  p_itens           jsonb,
  p_tipo_entrega    text,
  p_forma_pagamento text,
  p_endereco_id     bigint  default null,
  p_troco_para      integer default null,
  p_cupom           text    default null,
  p_observacao      text    default null
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
begin
  if v_uid is null then
    raise exception 'Entre na sua conta para fazer o pedido.' using hint = 'NAO_AUTENTICADO';
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

  -- Nome e telefone vêm do perfil autenticado, nunca do app
  select nome, telefone into v_perfil from public.perfis where id = v_uid;
  if not found or nullif(btrim(v_perfil.nome), '') is null then
    raise exception 'Complete seu cadastro (nome) para fazer o pedido.' using hint = 'VALIDACAO';
  end if;
  if nullif(btrim(v_perfil.telefone), '') is null then
    raise exception 'Cadastre seu telefone no perfil para fazer o pedido.' using hint = 'VALIDACAO';
  end if;

  -- R5: entrega exige endereço do próprio cliente; guarda uma fotografia dele
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

  -- R6: troco só em dinheiro e maior ou igual ao total
  if p_troco_para is not null then
    if p_forma_pagamento <> 'dinheiro' then
      raise exception 'Troco só vale para pagamento em dinheiro.' using hint = 'VALIDACAO';
    end if;
    if p_troco_para < v_total then
      raise exception 'O troco deve ser para um valor maior ou igual ao total.' using hint = 'VALIDACAO';
    end if;
  end if;

  -- "numero" é IDENTITY: não é informado, o banco gera
  insert into public.pedidos (cliente_id, cliente_nome, cliente_telefone,
                              tipo_entrega, endereco_id, endereco_entrega,
                              forma_pagamento, troco_para, observacao,
                              cupom_id, subtotal, desconto, taxa_entrega, total, status)
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
          'recebido')
  returning id, numero into v_pedido_id, v_numero;

  for v_item in select value from jsonb_array_elements(v_itens) loop
    -- campos legados que o painel Web lê: nome e sabores
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

  -- Pagamento simulado: pix e cartão aprovam na hora; dinheiro fica pendente
  insert into public.pagamentos (pedido_id, forma, status, valor, troco_para)
  values (v_pedido_id, p_forma_pagamento,
          case when p_forma_pagamento = 'dinheiro' then 'pendente' else 'aprovado' end,
          v_total, p_troco_para);

  insert into public.pedido_status_historico (pedido_id, status, alterado_por)
  values (v_pedido_id, 'recebido', v_uid);

  return jsonb_build_object('id', v_pedido_id, 'numero', v_numero,
                            'status', 'recebido', 'itens', v_itens)
         || (v_totais - 'cupomId');
end;
$$;

-- ---------------------------------------------------------------------
-- 3) alterar_status: só admin, status do painel Web
--    recebido → em_preparo → saiu_para_entrega → entregue   (entrega)
--                         └→ entregue                        (retirada)
--    recebido / em_preparo → cancelado
-- ---------------------------------------------------------------------
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
    when 'recebido'          then array['em_preparo', 'cancelado']
    when 'em_preparo'        then case v_pedido.tipo_entrega
                                    when 'entrega' then array['saiu_para_entrega', 'cancelado']
                                    else array['entregue', 'cancelado'] end
    when 'saiu_para_entrega' then array['entregue']
    else array[]::text[]
  end;

  if not (p_status = any (v_validos)) then
    raise exception 'Não é possível mudar de "%" para "%".', v_pedido.status, p_status
      using hint = 'TRANSICAO_INVALIDA';
  end if;

  update public.pedidos set status = p_status where id = p_pedido_id;

  return jsonb_build_object('id', p_pedido_id, 'status', p_status, 'statusAnterior', v_pedido.status);
end;
$$;

-- ---------------------------------------------------------------------
-- 4) cancelar_pedido: o próprio cliente, só enquanto "recebido"
-- ---------------------------------------------------------------------
create or replace function public.cancelar_pedido(p_pedido_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := (select auth.uid());
  v_pedido record;
begin
  if v_uid is null then
    raise exception 'Entre na sua conta.' using hint = 'NAO_AUTENTICADO';
  end if;

  select id, status, cliente_id into v_pedido
    from public.pedidos where id = p_pedido_id for update;
  -- "is distinct from": pedido legado sem cliente_id nunca é cancelável por cliente
  if not found or v_pedido.cliente_id is distinct from v_uid then
    raise exception 'Pedido % não encontrado.', p_pedido_id using hint = 'NAO_ENCONTRADO';
  end if;
  if v_pedido.status <> 'recebido' then
    raise exception 'O pedido já está em preparo e não pode mais ser cancelado pelo app.'
      using hint = 'TRANSICAO_INVALIDA';
  end if;

  update public.pedidos set status = 'cancelado' where id = p_pedido_id;

  return jsonb_build_object('id', p_pedido_id, 'status', 'cancelado');
end;
$$;

-- ---------------------------------------------------------------------
-- 5) Permissões das assinaturas atuais
-- ---------------------------------------------------------------------
revoke execute on function public.criar_pedido(jsonb, text, text, bigint, integer, text, text) from public, anon;
revoke execute on function public.alterar_status(uuid, text) from public, anon;
revoke execute on function public.cancelar_pedido(uuid) from public, anon;

grant execute on function public.criar_pedido(jsonb, text, text, bigint, integer, text, text) to authenticated;
grant execute on function public.alterar_status(uuid, text) to authenticated;
grant execute on function public.cancelar_pedido(uuid) to authenticated;

commit;
