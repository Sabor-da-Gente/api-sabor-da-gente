-- =====================================================================
-- Sabor da Gente — 4/5: Realtime
--
-- Publica mudanças de pedidos e do histórico de status. O Supabase
-- respeita o RLS: cada cliente só recebe avisos dos próprios pedidos;
-- o admin recebe de todos.
--   App:    acompanha o status do pedido sem ficar consultando.
--   Painel: vê pedidos novos chegando na hora.
-- =====================================================================
alter publication supabase_realtime add table public.pedidos, public.pedido_status_historico;
