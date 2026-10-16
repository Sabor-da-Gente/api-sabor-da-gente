#!/bin/bash
# Recria o banco de teste e aplica todas as migrations em ordem.
# Uso: PGHOST=localhost PGUSER=postgres ./testes/recriar_banco.sh
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
BANCO="${BANCO_TESTE:-sabor_teste}"
P="psql -v ON_ERROR_STOP=1 -q"
$P -d postgres -c "drop database if exists $BANCO with (force)" -c "create database $BANCO"
$P -d "$BANCO" -f "$DIR/shim_supabase.sql" 2>/dev/null
for f in "$DIR"/../supabase/migrations/*.sql; do
  $P -d "$BANCO" -f "$f" > /dev/null
  echo "aplicada: $(basename "$f")"
done
