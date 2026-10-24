-- Realtime idempotente (substitui a 120300): só adiciona o que ainda não está publicado.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables
                    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'pedidos') then
      alter publication supabase_realtime add table public.pedidos;
    end if;
    if not exists (select 1 from pg_publication_tables
                    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'pedido_status_historico') then
      alter publication supabase_realtime add table public.pedido_status_historico;
    end if;
  end if;
end;
$$;
