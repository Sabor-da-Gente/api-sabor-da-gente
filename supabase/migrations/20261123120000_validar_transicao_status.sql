-- =====================================================================
-- Sabor da Gente — valida no banco as transições de status dos pedidos
-- (ref.: Web issue #12, Issue 03 — fluxo de status e cancelamento)
--
-- Fluxo permitido:
--   recebido             -> em_preparo | cancelado
--   em_preparo           -> saiu_para_entrega (entrega) | pronto_para_retirada (retirada)
--   saiu_para_entrega    -> entregue
--   pronto_para_retirada -> entregue
--   entregue / cancelado -> sem transições
-- Cancelamento feito pelo admin exige mensagem em motivo_cancelamento.
-- Vale para qualquer caminho de escrita (.update() do painel e RPCs).
-- O histórico continua a cargo de trg_pedidos_historico_status.
-- =====================================================================
begin;

alter table public.pedidos add column if not exists motivo_cancelamento text;

create or replace function public.validar_transicao_status()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_validos text[];
begin
  v_validos := case old.status
    when 'recebido'             then array['em_preparo', 'cancelado']
    when 'em_preparo'           then case old.tipo_entrega
                                       when 'entrega' then array['saiu_para_entrega']
                                       else array['pronto_para_retirada'] end
    when 'saiu_para_entrega'    then array['entregue']
    when 'pronto_para_retirada' then array['entregue']
    else array[]::text[]
  end;

  if not (new.status = any (v_validos)) then
    raise exception 'Não é possível mudar de "%" para "%".', old.status, new.status
      using hint = 'TRANSICAO_INVALIDA';
  end if;

  if new.status = 'cancelado'
     and public.eh_admin()
     and nullif(btrim(coalesce(new.motivo_cancelamento, '')), '') is null then
    raise exception 'Informe a mensagem para o cliente ao cancelar o pedido.'
      using hint = 'VALIDACAO';
  end if;

  return new;
end;
$$;

revoke execute on function public.validar_transicao_status() from public, anon, authenticated;

drop trigger if exists trg_pedidos_validar_status on public.pedidos;
create trigger trg_pedidos_validar_status
  before update of status on public.pedidos
  for each row
  when (old.status is distinct from new.status)
  execute function public.validar_transicao_status();

commit;
