-- =====================================================================
-- Sabor da Gente — 3/5: funções (regras de negócio)
--
-- Chamadas pelo app e pelo painel com supabase.rpc('nome', { ...params }).
-- Rodam como "security definer": gravam em tabelas que o cliente não pode
-- alterar direto, mas SÓ depois de validar tudo. O app manda IDs e
-- quantidades; os preços são sempre calculados aqui (regra R3).
--
-- Erros: a mensagem é pensada para mostrar ao usuário; o campo "hint"
-- traz um código fixo para o app tratar:
--   NAO_AUTENTICADO · SEM_PERMISSAO · VALIDACAO · INDISPONIVEL ·
--   NAO_ENCONTRADO · TRANSICAO_INVALIDA
-- =====================================================================

-- ---------------------------------------------------------------------
-- (interna) Valida e precifica os itens do pedido — regras R1 e R2
--
-- Entrada (jsonb), uma lista de itens:
--   { "tipo": "produto", "produtoId": 1, "quantidade": 6, "observacao": "..." }
--   { "tipo": "pizza", "tamanhoId": 2, "massaId": 1, "saborIds": [1, 3],
--     "adicionalIds": [1], "quantidade": 1, "observacao": "..." }
-- Saída: a mesma lista com descricao, precoUnitario, subtotal e nomes.
-- ---------------------------------------------------------------------
create function public.calcular_itens(p_itens jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_item        jsonb;
  v_pos         integer := 0;
  v_res         jsonb := '[]'::jsonb;
  v_tipo        text;
  v_qtd         integer;
  v_obs         text;
  v_regra       text;
  v_prod        record;
  v_tam         record;
  v_massa       record;
  v_sabor_ids   bigint[];
  v_adic_ids    bigint[];
  v_sabores     jsonb;
  v_adicionais  jsonb;
  v_qtd_achados integer;
  v_maior       integer;
  v_media       integer;
  v_soma_adic   integer;
  v_preco_sab   integer;
  v_unit        integer;
  v_desc        text;
begin
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'O pedido precisa ter pelo menos 1 item.' using hint = 'VALIDACAO';
  end if;
  if jsonb_array_length(p_itens) > 30 then
    raise exception 'O pedido pode ter no máximo 30 itens.' using hint = 'VALIDACAO';
  end if;

  select valor into v_regra from public.configuracoes where chave = 'regra_preco_pizza';
  v_regra := coalesce(v_regra, 'maior');

  for v_item in select value from jsonb_array_elements(p_itens) loop
    v_pos  := v_pos + 1;
    v_tipo := v_item ->> 'tipo';

    if coalesce(v_item ->> 'quantidade', '') !~ '^\d{1,3}$' then
      raise exception 'Item %: quantidade inválida.', v_pos using hint = 'VALIDACAO';
    end if;
    v_qtd := (v_item ->> 'quantidade')::integer;
    if v_qtd < 1 or v_qtd > 50 then
      raise exception 'Item %: a quantidade deve ser de 1 a 50.', v_pos using hint = 'VALIDACAO';
    end if;

    v_obs := nullif(btrim(v_item ->> 'observacao'), '');
    if length(v_obs) > 200 then
      raise exception 'Item %: a observação pode ter até 200 caracteres.', v_pos using hint = 'VALIDACAO';
    end if;

    if v_tipo = 'produto' then
      select p.id, p.nome, p.preco
        into v_prod
        from public.produtos p
        join public.categorias c on c.id = p.categoria_id
       where p.id = (v_item ->> 'produtoId')::bigint
         and p.ativo and c.ativa;
      if not found then
        raise exception 'Item %: produto indisponível.', v_pos using hint = 'INDISPONIVEL';
      end if;

      v_res := v_res || jsonb_build_array(jsonb_build_object(
        'tipo', 'produto',
        'produtoId', v_prod.id,
        'descricao', v_prod.nome,
        'quantidade', v_qtd,
        'precoUnitario', v_prod.preco,
        'subtotal', v_prod.preco * v_qtd,
        'observacao', v_obs
      ));

    elsif v_tipo = 'pizza' then
      select id, nome, max_sabores into v_tam
        from public.tamanhos where id = (v_item ->> 'tamanhoId')::bigint and ativo;
      if not found then
        raise exception 'Item %: tamanho indisponível.', v_pos using hint = 'INDISPONIVEL';
      end if;

      select id, nome, acrescimo into v_massa
        from public.massas where id = (v_item ->> 'massaId')::bigint and ativo;
      if not found then
        raise exception 'Item %: massa indisponível.', v_pos using hint = 'INDISPONIVEL';
      end if;

      -- R2: de 1 a max_sabores, sem repetir
      v_sabor_ids := array(
        select jsonb_array_elements_text(coalesce(v_item -> 'saborIds', '[]'::jsonb))::bigint);
      if cardinality(v_sabor_ids) < 1 or cardinality(v_sabor_ids) > v_tam.max_sabores then
        raise exception 'Item %: escolha de 1 a % sabores para o tamanho %.',
          v_pos, v_tam.max_sabores, v_tam.nome using hint = 'VALIDACAO';
      end if;
      if cardinality(v_sabor_ids) <> (select count(distinct s) from unnest(v_sabor_ids) s) then
        raise exception 'Item %: o mesmo sabor foi escolhido duas vezes.', v_pos using hint = 'VALIDACAO';
      end if;

      select jsonb_agg(jsonb_build_object('id', s.id, 'nome', s.nome, 'preco', sp.preco)
                       order by array_position(v_sabor_ids, s.id)),
             count(*), max(sp.preco), ceil(avg(sp.preco))::integer
        into v_sabores, v_qtd_achados, v_maior, v_media
        from public.sabores s
        join public.sabor_precos sp on sp.sabor_id = s.id and sp.tamanho_id = v_tam.id
       where s.id = any (v_sabor_ids) and s.ativo;
      if v_qtd_achados <> cardinality(v_sabor_ids) then
        raise exception 'Item %: um dos sabores não está disponível no tamanho %.',
          v_pos, v_tam.nome using hint = 'INDISPONIVEL';
      end if;

      -- Adicionais (opcionais, sem repetir)
      v_adic_ids := array(
        select jsonb_array_elements_text(coalesce(v_item -> 'adicionalIds', '[]'::jsonb))::bigint);
      if cardinality(v_adic_ids) <> (select count(distinct a) from unnest(v_adic_ids) a) then
        raise exception 'Item %: o mesmo adicional foi escolhido duas vezes.', v_pos using hint = 'VALIDACAO';
      end if;
      select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'nome', a.nome, 'preco', a.preco)
                                order by a.nome), '[]'::jsonb),
             count(*), coalesce(sum(a.preco), 0)
        into v_adicionais, v_qtd_achados, v_soma_adic
        from public.adicionais a
       where a.id = any (v_adic_ids) and a.ativo;
      if v_qtd_achados <> cardinality(v_adic_ids) then
        raise exception 'Item %: um dos adicionais está indisponível.', v_pos using hint = 'INDISPONIVEL';
      end if;

      -- R1: preço dos sabores (maior ou média) + massa + adicionais
      v_preco_sab := case when v_regra = 'media' then v_media else v_maior end;
      v_unit := v_preco_sab + v_massa.acrescimo + v_soma_adic;
      v_desc := format('Pizza %s (%s) — %s', v_tam.nome, v_massa.nome,
                       (select string_agg(x ->> 'nome', ' / ') from jsonb_array_elements(v_sabores) x));

      v_res := v_res || jsonb_build_array(jsonb_build_object(
        'tipo', 'pizza',
        'tamanho', jsonb_build_object('id', v_tam.id, 'nome', v_tam.nome),
        'massa', jsonb_build_object('id', v_massa.id, 'nome', v_massa.nome, 'acrescimo', v_massa.acrescimo),
        'sabores', v_sabores,
        'adicionais', v_adicionais,
        'descricao', v_desc,
        'quantidade', v_qtd,
        'precoUnitario', v_unit,
        'subtotal', v_unit * v_qtd,
        'observacao', v_obs
      ));

    else
      raise exception 'Item %: tipo deve ser "produto" ou "pizza".', v_pos using hint = 'VALIDACAO';
    end if;
  end loop;

  return v_res;
end;
$$;

-- ---------------------------------------------------------------------
-- (interna) Totais do pedido — regras R4 e R8
-- ---------------------------------------------------------------------
create function public.calcular_totais(p_itens_calculados jsonb, p_tipo_entrega text, p_cupom text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_subtotal integer;
  v_taxa     integer := 0;
  v_desconto integer := 0;
  v_cupom    record;
  v_cupom_id bigint;
  v_usos     integer;
  v_avisos   jsonb := '[]'::jsonb;
begin
  select coalesce(sum((x ->> 'subtotal')::integer), 0) into v_subtotal
    from jsonb_array_elements(p_itens_calculados) x;

  if p_tipo_entrega = 'entrega' then
    select coalesce(valor::integer, 0) into v_taxa from public.configuracoes where chave = 'taxa_entrega';
    v_taxa := coalesce(v_taxa, 0);
  end if;

  if nullif(btrim(p_cupom), '') is not null then
    select * into v_cupom from public.cupons where lower(codigo) = lower(btrim(p_cupom));
    if not found or not v_cupom.ativo
       or (v_cupom.valido_de is not null and now() < v_cupom.valido_de)
       or (v_cupom.valido_ate is not null and now() > v_cupom.valido_ate) then
      raise exception 'Cupom inválido ou expirado.' using hint = 'VALIDACAO';
    end if;
    if v_subtotal < v_cupom.valor_minimo_pedido then
      raise exception 'Este cupom vale para pedidos a partir de R$ %.',
        replace(to_char(v_cupom.valor_minimo_pedido / 100.0, 'FM999990.00'), '.', ',')
        using hint = 'VALIDACAO';
    end if;
    if v_cupom.usos_maximos is not null then
      select count(*) into v_usos from public.pedidos
       where cupom_id = v_cupom.id and status <> 'cancelado';
      if v_usos >= v_cupom.usos_maximos then
        raise exception 'Este cupom já atingiu o limite de usos.' using hint = 'VALIDACAO';
      end if;
    end if;

    v_desconto := case v_cupom.tipo
                    when 'percentual' then floor(v_subtotal * v_cupom.valor / 100.0)::integer
                    else v_cupom.valor
                  end;
    v_desconto := least(v_desconto, v_subtotal);
    v_cupom_id := v_cupom.id;
    v_avisos := v_avisos || to_jsonb(format('Cupom %s aplicado.', upper(v_cupom.codigo)));
  end if;

  return jsonb_build_object(
    'subtotal', v_subtotal,
    'desconto', v_desconto,
    'taxaEntrega', v_taxa,
    'total', v_subtotal - v_desconto + v_taxa,
    'cupomId', v_cupom_id,
    'avisos', v_avisos
  );
end;
$$;

-- ---------------------------------------------------------------------
-- calcular_pedido: simula sem gravar (tela de revisão)
-- ---------------------------------------------------------------------
create function public.calcular_pedido(
  p_itens        jsonb,
  p_tipo_entrega text default 'entrega',
  p_cupom        text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_itens  jsonb;
  v_totais jsonb;
begin
  if p_tipo_entrega not in ('entrega', 'retirada') then
    raise exception 'Escolha entrega ou retirada.' using hint = 'VALIDACAO';
  end if;
  v_itens  := public.calcular_itens(p_itens);
  v_totais := public.calcular_totais(v_itens, p_tipo_entrega, p_cupom);
  return jsonb_build_object('itens', v_itens) || (v_totais - 'cupomId');
end;
$$;

-- ---------------------------------------------------------------------
-- criar_pedido: valida, recalcula e grava tudo numa transação (R9)
-- ---------------------------------------------------------------------
create function public.criar_pedido(
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
  v_uid       uuid := (select auth.uid());
  v_end       record;
  v_end_texto text;
  v_itens     jsonb;
  v_totais    jsonb;
  v_total     integer;
  v_pedido_id bigint;
  v_item_id   bigint;
  v_item      jsonb;
  v_sub       jsonb;
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

  insert into public.pedidos (cliente_id, tipo_entrega, endereco_id, endereco_entrega, observacao,
                              cupom_id, subtotal, desconto, taxa_entrega, total)
  values (v_uid, p_tipo_entrega,
          case when p_tipo_entrega = 'entrega' then p_endereco_id end,
          v_end_texto,
          nullif(btrim(p_observacao), ''),
          (v_totais ->> 'cupomId')::bigint,
          (v_totais ->> 'subtotal')::integer,
          (v_totais ->> 'desconto')::integer,
          (v_totais ->> 'taxaEntrega')::integer,
          v_total)
  returning id into v_pedido_id;

  for v_item in select value from jsonb_array_elements(v_itens) loop
    insert into public.itens_pedido (pedido_id, tipo, produto_id, tamanho_id, massa_id, descricao,
                                     quantidade, preco_unitario, subtotal, observacao)
    values (v_pedido_id,
            v_item ->> 'tipo',
            (v_item ->> 'produtoId')::bigint,
            (v_item -> 'tamanho' ->> 'id')::bigint,
            (v_item -> 'massa' ->> 'id')::bigint,
            v_item ->> 'descricao',
            (v_item ->> 'quantidade')::integer,
            (v_item ->> 'precoUnitario')::integer,
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
  values (v_pedido_id, 'realizado', v_uid);

  return jsonb_build_object('id', v_pedido_id, 'status', 'realizado', 'itens', v_itens)
         || (v_totais - 'cupomId');
end;
$$;

-- ---------------------------------------------------------------------
-- alterar_status: só admin, seguindo o fluxo (R7)
--   realizado → em_preparacao → saiu_para_entrega → entregue      (entrega)
--                            └→ pronto_para_retirada → entregue   (retirada)
--   realizado / em_preparacao → cancelado
-- ---------------------------------------------------------------------
create function public.alterar_status(p_pedido_id bigint, p_status text)
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
    when 'realizado'            then array['em_preparacao', 'cancelado']
    when 'em_preparacao'        then case v_pedido.tipo_entrega
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

  update public.pedidos set status = p_status where id = p_pedido_id;
  insert into public.pedido_status_historico (pedido_id, status, alterado_por)
  values (p_pedido_id, p_status, (select auth.uid()));

  return jsonb_build_object('id', p_pedido_id, 'status', p_status, 'statusAnterior', v_pedido.status);
end;
$$;

-- ---------------------------------------------------------------------
-- cancelar_pedido: o próprio cliente, só enquanto "realizado"
-- ---------------------------------------------------------------------
create function public.cancelar_pedido(p_pedido_id bigint)
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
  if not found or v_pedido.cliente_id <> v_uid then
    raise exception 'Pedido % não encontrado.', p_pedido_id using hint = 'NAO_ENCONTRADO';
  end if;
  if v_pedido.status <> 'realizado' then
    raise exception 'O pedido já está em preparo e não pode mais ser cancelado pelo app.'
      using hint = 'TRANSICAO_INVALIDA';
  end if;

  update public.pedidos set status = 'cancelado' where id = p_pedido_id;
  insert into public.pedido_status_historico (pedido_id, status, alterado_por)
  values (p_pedido_id, 'cancelado', v_uid);

  return jsonb_build_object('id', p_pedido_id, 'status', 'cancelado');
end;
$$;

-- ---------------------------------------------------------------------
-- estatisticas_vendas: painel do admin
-- ---------------------------------------------------------------------
create function public.estatisticas_vendas(
  p_de  date default (current_date - 30),
  p_ate date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_res jsonb;
begin
  if not public.eh_admin() then
    raise exception 'Apenas a pizzaria pode ver as estatísticas.' using hint = 'SEM_PERMISSAO';
  end if;

  with periodo as (
    select * from public.pedidos
     where criado_em >= p_de::timestamptz and criado_em < (p_ate + 1)::timestamptz
  ),
  validos as (select * from periodo where status <> 'cancelado'),
  vendidos as (
    select 'sabor' as tipo, s.sabor_id as id, s.nome, sum(i.quantidade)::integer as quantidade
      from validos v join public.itens_pedido i on i.pedido_id = v.id
      join public.itens_pedido_sabores s on s.item_id = i.id
     group by s.sabor_id, s.nome
    union all
    select 'produto', i.produto_id, i.descricao, sum(i.quantidade)::integer
      from validos v join public.itens_pedido i on i.pedido_id = v.id
     where i.tipo = 'produto'
     group by i.produto_id, i.descricao
  )
  select jsonb_build_object(
    'periodo', jsonb_build_object('de', p_de, 'ate', p_ate),
    'pedidos', (select count(*) from periodo),
    'cancelados', (select count(*) from periodo where status = 'cancelado'),
    'faturamento', (select coalesce(sum(total), 0) from validos),
    'ticketMedio', (select coalesce(round(avg(total))::integer, 0) from validos),
    'porStatus', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb)
                    from (select status, count(*) n from periodo group by status) x),
    'porDia', (select coalesce(jsonb_agg(jsonb_build_object('data', d, 'pedidos', n, 'faturamento', f) order by d), '[]'::jsonb)
                 from (select (criado_em at time zone 'America/Sao_Paulo')::date d, count(*) n, sum(total) f
                         from validos group by 1) x),
    'maisVendidos', (select coalesce(jsonb_agg(to_jsonb(v) order by v.quantidade desc), '[]'::jsonb)
                       from (select * from vendidos order by quantidade desc limit 10) v)
  ) into v_res;

  return v_res;
end;
$$;

-- ---------------------------------------------------------------------
-- Quem pode chamar o quê
-- ---------------------------------------------------------------------
revoke execute on function public.calcular_itens(jsonb) from public, anon, authenticated;
revoke execute on function public.calcular_totais(jsonb, text, text) from public, anon, authenticated;
revoke execute on function public.criar_perfil_novo_usuario() from public, anon, authenticated;
revoke execute on function public.tocar_atualizado_em() from public, anon, authenticated;

revoke execute on function public.calcular_pedido(jsonb, text, text) from public, anon;
revoke execute on function public.criar_pedido(jsonb, text, text, bigint, integer, text, text) from public, anon;
revoke execute on function public.alterar_status(bigint, text) from public, anon;
revoke execute on function public.cancelar_pedido(bigint) from public, anon;
revoke execute on function public.estatisticas_vendas(date, date) from public, anon;

grant execute on function public.calcular_pedido(jsonb, text, text) to authenticated;
grant execute on function public.criar_pedido(jsonb, text, text, bigint, integer, text, text) to authenticated;
grant execute on function public.alterar_status(bigint, text) to authenticated;
grant execute on function public.cancelar_pedido(bigint) to authenticated;
grant execute on function public.estatisticas_vendas(date, date) to authenticated;
