"""Testa as migrations num PostgreSQL que simula o Supabase.

Cada bloco roda como um papel do Supabase:
  anon          -> visitante sem login
  authenticated -> cliente ou admin, com o id do usuário em request.jwt.claim.sub
"""
import json
import os
import sys

import psycopg

DSN = os.environ.get("TESTE_DSN", "host=localhost port=5432 user=postgres dbname=sabor_teste")
ok = falhas = 0


def check(cond, msg):
    global ok, falhas
    if cond:
        ok += 1
        print(f"  ✔ {msg}")
    else:
        falhas += 1
        print(f"  ✘ {msg}")


conn = psycopg.connect(DSN, autocommit=True)


def como(papel, uid=None):
    conn.execute("reset role")
    conn.execute("select set_config('request.jwt.claim.sub', %s, false)", (uid or "",))
    if papel != "postgres":
        conn.execute(f"set role {papel}")


def q(sql, params=None):
    return conn.execute(sql, params).fetchall()


def erro(sql, params=None):
    """Executa esperando erro; devolve (mensagem, hint) ou None se não deu erro."""
    try:
        conn.execute(sql, params)
        return None
    except psycopg.Error as e:
        d = e.diag
        return (d.message_primary or str(e), d.message_hint)


def rpc(nome, **kw):
    args = ", ".join(f"{k} => %({k})s" for k in kw)
    vals = {k: (json.dumps(v) if isinstance(v, (list, dict)) else v) for k, v in kw.items()}
    return conn.execute(f"select public.{nome}({args})", vals).fetchone()[0]


def rpc_erro(nome, **kw):
    try:
        rpc(nome, **kw)
        return None
    except psycopg.Error as e:
        return (e.diag.message_primary, e.diag.message_hint)


# ---------------------------------------------------------------- usuários
como("postgres")
ana, bia, adm = [
    q("insert into auth.users (email, raw_user_meta_data) values (%s, %s) returning id",
      (email, json.dumps(meta)))[0][0].__str__()
    for email, meta in [
        ("ana@email.com", {"nome": "Ana Souza", "telefone": "83999990000"}),
        ("bia@email.com", {"nome": "Bia Lima"}),
        ("admin@sabordagente.com", {"nome": "Pizzaria"}),
    ]
]
q("update public.perfis set tipo = 'admin' where id = %s returning id", (adm,))

print("\n1. Cadastro no Auth cria o perfil automaticamente")
perfis = q("select nome, telefone, tipo from public.perfis order by nome")
check(("Ana Souza", "83999990000", "cliente") in perfis, "perfil da Ana criado com nome e telefone")
check(len(perfis) == 3, "3 perfis criados")

# ---------------------------------------------------------------- visitante
print("\n2. Visitante sem login (anon)")
como("anon")
check(q("select count(*) from public.categorias")[0][0] == 5, "lê as 5 categorias")
check(q("select count(*) from public.produtos")[0][0] == 11, "lê os 11 produtos")
check(q("select count(*) from public.sabor_precos")[0][0] == 6, "lê os preços dos sabores")
check(erro("select * from public.pedidos") is not None, "NÃO lê pedidos")
check(erro("select * from public.perfis") is not None, "NÃO lê perfis")
check(erro("select * from public.cupons") is not None, "NÃO lê cupons")
check(erro("update public.produtos set preco = 1") is not None, "NÃO altera produtos")
check(rpc_erro("criar_pedido", p_itens=[{"tipo": "produto", "produtoId": 1, "quantidade": 1}],
               p_tipo_entrega="retirada", p_forma_pagamento="pix") is not None,
      "NÃO cria pedido sem login")

# ---------------------------------------------------------------- cliente Ana
print("\n3. Cliente (Ana): perfil e endereços")
como("authenticated", ana)
check(erro("update public.perfis set tipo = 'admin' where id = auth.uid()") is not None,
      "NÃO consegue se promover a admin")
q("update public.perfis set nome = 'Ana S. Souza' where id = auth.uid() returning id")
check(q("select nome from public.perfis")[0][0] == "Ana S. Souza", "altera o próprio nome")
check(q("select count(*) from public.perfis")[0][0] == 1, "vê só o próprio perfil")
end_ana = q("""insert into public.enderecos (apelido, logradouro, numero, complemento, bairro, cidade)
               values ('Casa', 'Rua Solon de Lucena', '120', 'Apto 2', 'Centro', 'Esperança')
               returning id""")[0][0]
check(end_ana is not None, "cadastra endereço (usuario_id preenchido sozinho)")

como("authenticated", bia)
end_bia = q("""insert into public.enderecos (logradouro, numero, bairro, cidade)
               values ('Rua B', '5', 'Bairro B', 'Esperança') returning id""")[0][0]
check(q("select count(*) from public.enderecos")[0][0] == 1, "Bia vê só o endereço dela")
r = erro("insert into public.enderecos (usuario_id, logradouro, numero, bairro, cidade) values (%s,'x','1','y','z')", (ana,))
check(r is not None, "Bia NÃO cria endereço em nome da Ana")

print("\n4. Cliente (Ana): calcular e criar pedido")
como("authenticated", ana)
itens = [
    {"tipo": "pizza", "tamanhoId": 2, "massaId": 1, "saborIds": [1, 3], "adicionalIds": [1],
     "quantidade": 1, "observacao": "Bem assada"},
    {"tipo": "produto", "produtoId": 1, "quantidade": 6},
]
calc = rpc("calcular_pedido", p_itens=itens, p_tipo_entrega="entrega", p_cupom="bemvindo10")
check(calc["itens"][0]["precoUnitario"] == 5600, "pizza Grande Calabresa/Portuguesa + borda = R$ 56,00")
check(calc["itens"][0]["descricao"] == "Pizza Grande (Tradicional) — Calabresa / Portuguesa", "descrição da pizza")
check((calc["subtotal"], calc["desconto"], calc["taxaEntrega"], calc["total"]) == (8000, 800, 500, 7700),
      f"totais com cupom 10%: {calc['subtotal']}/{calc['desconto']}/{calc['taxaEntrega']}/{calc['total']}")

ped = rpc("criar_pedido", p_itens=itens, p_tipo_entrega="entrega", p_forma_pagamento="dinheiro",
          p_endereco_id=end_ana, p_troco_para=10000, p_observacao="Sem cebola")
pid = ped["id"]
check(ped["total"] == 8500 and ped["status"] == "realizado", f"pedido #{pid} criado: total R$ 85,00")
row = q("select endereco_entrega, total from public.pedidos where id = %s", (pid,))[0]
check(row[0] == "Rua Solon de Lucena, 120, Apto 2 — Centro, Esperança/PB", "endereço guardado como fotografia")
check(q("select count(*) from public.itens_pedido where pedido_id = %s", (pid,))[0][0] == 2, "2 itens gravados")
check(q("""select count(*) from public.itens_pedido_sabores s join public.itens_pedido i on i.id = s.item_id
           where i.pedido_id = %s""", (pid,))[0][0] == 2, "2 sabores gravados com preço da época")
check(q("select forma, status, troco_para from public.pagamentos where pedido_id = %s", (pid,))[0]
      == ("dinheiro", "pendente", 10000), "pagamento em dinheiro pendente, troco R$ 100")
check(q("select status from public.pedido_status_historico where pedido_id = %s", (pid,)) == [("realizado",)],
      "histórico começa em 'realizado'")

print("\n5. Validações do pedido")
def tenta(desc, hint, **kw):
    base = dict(p_tipo_entrega="retirada", p_forma_pagamento="pix")
    base.update(kw)
    r = rpc_erro("criar_pedido", **base)
    check(r is not None and r[1] == hint, f"{desc} → {r[1] if r else 'NÃO deu erro'}: {r[0] if r else ''}")

tenta("3 sabores na Grande", "VALIDACAO",
      p_itens=[{"tipo": "pizza", "tamanhoId": 2, "massaId": 1, "saborIds": [1, 2, 3], "quantidade": 1}])
tenta("sabor repetido", "VALIDACAO",
      p_itens=[{"tipo": "pizza", "tamanhoId": 2, "massaId": 1, "saborIds": [1, 1], "quantidade": 1}])
tenta("quantidade 0", "VALIDACAO", p_itens=[{"tipo": "produto", "produtoId": 1, "quantidade": 0}])
tenta("produto que não existe", "INDISPONIVEL", p_itens=[{"tipo": "produto", "produtoId": 999, "quantidade": 1}])
tenta("troco no pix", "VALIDACAO", p_itens=[{"tipo": "produto", "produtoId": 1, "quantidade": 1}], p_troco_para=1000)
tenta("troco menor que o total", "VALIDACAO", p_itens=[{"tipo": "produto", "produtoId": 1, "quantidade": 1}],
      p_forma_pagamento="dinheiro", p_troco_para=100)
tenta("entrega no endereço da Bia", "VALIDACAO", p_itens=[{"tipo": "produto", "produtoId": 1, "quantidade": 1}],
      p_tipo_entrega="entrega", p_endereco_id=end_bia)
tenta("cupom inexistente", "VALIDACAO", p_itens=[{"tipo": "produto", "produtoId": 1, "quantidade": 10}], p_cupom="NAOEXISTE")
tenta("cupom abaixo do mínimo", "VALIDACAO", p_itens=[{"tipo": "produto", "produtoId": 1, "quantidade": 1}], p_cupom="BEMVINDO10")
r = rpc("calcular_pedido", p_itens=[{"tipo": "produto", "produtoId": 1, "quantidade": 1, "precoUnitario": 1}],
        p_tipo_entrega="retirada")
check(r["total"] == 400, "preço mandado pelo app é ignorado (retirada sem taxa = R$ 4,00)")

print("\n6. Cliente NÃO grava direto nem mexe no que não é dele")
check(erro("insert into public.pedidos (cliente_id, tipo_entrega, subtotal, total) values (auth.uid(), 'retirada', 0, 0)") is not None,
      "NÃO insere pedido direto na tabela")
check(erro("update public.pedidos set status = 'entregue'") is not None, "NÃO altera status direto")
r = rpc_erro("alterar_status", p_pedido_id=pid, p_status="em_preparacao")
check(r is not None and r[1] == "SEM_PERMISSAO", "NÃO usa alterar_status")
q("update public.produtos set preco = 1 where id = 1 returning id")
como("postgres")
check(q("select preco from public.produtos where id = 1")[0][0] == 400, "tentativa de mudar preço não teve efeito")
como("authenticated", ana)
check(erro("insert into public.produtos (categoria_id, nome, preco) values (2, 'Hack', 1)") is not None,
      "NÃO cadastra produto")
check(rpc_erro("estatisticas_vendas") is not None, "NÃO vê estatísticas")

como("authenticated", bia)
check(q("select count(*) from public.pedidos")[0][0] == 0, "Bia NÃO vê o pedido da Ana")
check(q("select count(*) from public.itens_pedido")[0][0] == 0, "Bia NÃO vê os itens da Ana")
r = rpc_erro("cancelar_pedido", p_pedido_id=pid)
check(r is not None and r[1] == "NAO_ENCONTRADO", "Bia NÃO cancela o pedido da Ana")

print("\n7. Admin: fluxo de status")
como("authenticated", adm)
check(q("select count(*) from public.pedidos")[0][0] == 1, "admin vê todos os pedidos")
r = rpc_erro("alterar_status", p_pedido_id=pid, p_status="entregue")
check(r is not None and r[1] == "TRANSICAO_INVALIDA", f"pular etapa é bloqueado: {r[0] if r else ''}")
r = rpc_erro("alterar_status", p_pedido_id=pid, p_status="pronto_para_retirada")
for st in ["em_preparacao", "saiu_para_entrega", "entregue"]:
    rpc("alterar_status", p_pedido_id=pid, p_status=st)
check(r is not None and r[1] == "TRANSICAO_INVALIDA", "'pronto para retirada' bloqueado em pedido de entrega")
hist = [h[0] for h in q("select status from public.pedido_status_historico where pedido_id = %s order by id", (pid,))]
check(hist == ["realizado", "em_preparacao", "saiu_para_entrega", "entregue"], f"histórico: {' → '.join(hist)}")
check(q("select count(distinct alterado_por) from public.pedido_status_historico where pedido_id = %s", (pid,))[0][0] == 2,
      "histórico registra quem mudou (cliente e admin)")
q("update public.pagamentos set status = 'aprovado' where pedido_id = %s returning id", (pid,))
check(q("select status from public.pagamentos where pedido_id = %s", (pid,))[0][0] == "aprovado", "admin aprova pagamento")
est = rpc("estatisticas_vendas")
check(est["pedidos"] == 1 and est["faturamento"] == 8500, f"estatísticas: {est['pedidos']} pedido, R$ {est['faturamento']/100:.2f}")
check(est["maisVendidos"][0]["nome"] == "Esfiha de Carne", "mais vendido: Esfiha de Carne (6 un.)")

print("\n8. Admin: cardápio")
q("update public.produtos set ativo = false where id = 2 returning id")
novo = q("insert into public.produtos (categoria_id, nome, preco) values (3, 'Suco de laranja', 700) returning id")[0][0]
check(novo > 11, f"admin cadastra produto (id {novo}, sem colidir com os IDs do cardápio inicial)")
como("anon")
check(q("select count(*) from public.produtos")[0][0] == 11, "visitante não vê o produto desativado")
como("authenticated", ana)
tenta("pedir produto desativado", "INDISPONIVEL", p_itens=[{"tipo": "produto", "produtoId": 2, "quantidade": 1}])
como("authenticated", adm)
q("update public.configuracoes set valor = 'media' where chave = 'regra_preco_pizza' returning chave")
r = rpc("calcular_pedido", p_itens=[{"tipo": "pizza", "tamanhoId": 2, "massaId": 1, "saborIds": [1, 3], "quantidade": 1}],
        p_tipo_entrega="retirada")
check(r["total"] == 4650, "regra 'media': Calabresa 45 + Portuguesa 48 → R$ 46,50")
q("update public.configuracoes set valor = 'maior' where chave = 'regra_preco_pizza' returning chave")

print("\n9. Cliente: cancelamento")
como("authenticated", ana)
p2 = rpc("criar_pedido", p_itens=[{"tipo": "produto", "produtoId": 9, "quantidade": 2}],
         p_tipo_entrega="retirada", p_forma_pagamento="pix")["id"]
check(rpc("cancelar_pedido", p_pedido_id=p2)["status"] == "cancelado", "cancela enquanto 'realizado'")
r = rpc_erro("cancelar_pedido", p_pedido_id=pid)
check(r is not None and r[1] == "TRANSICAO_INVALIDA", "NÃO cancela pedido já entregue")
check(q("select count(*) from public.pedidos")[0][0] == 2, "histórico da Ana: 2 pedidos")

print(f"\nResultado: {ok} ok, {falhas} falha(s)")
sys.exit(1 if falhas else 0)
