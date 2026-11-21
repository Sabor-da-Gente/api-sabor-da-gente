#!/bin/bash
# Recria o banco de teste imitando o banco REAL (legado) e aplica as migrations
# na mesma ordem da tabela "Migrations aplicadas" do README.
# Uso: PGHOST=localhost PGUSER=postgres ./testes/recriar_banco.sh
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
MIG="$DIR/../supabase/migrations"
BANCO="${BANCO_TESTE:-sabor_teste}"
P="psql -v ON_ERROR_STOP=1 -q"

ORDEM=(
  20261016120500_adaptar_schema_existente.sql
  20261024135000_funcoes_base.sql
  20261024141000_seguranca_legado.sql
  20261016120200_funcoes.sql
  20261024140000_corrigir_funcoes_pedidos.sql
  20261024142000_catalogo_novo.sql
  20261024143000_realtime_legado.sql
  20261024150000_status_pronto_retirada.sql
  20261121120000_idempotencia_criar_pedido.sql
)

$P -d postgres -c "drop database if exists $BANCO with (force)" -c "create database $BANCO"
$P -d "$BANCO" -f "$DIR/shim_supabase.sql" 2>/dev/null
$P -d "$BANCO" -f "$DIR/schema_legado.sql" > /dev/null
for f in "${ORDEM[@]}"; do
  $P -d "$BANCO" -f "$MIG/$f" > /dev/null 2>&1 || { $P -d "$BANCO" -f "$MIG/$f"; exit 1; }
  echo "aplicada: $f"
done
