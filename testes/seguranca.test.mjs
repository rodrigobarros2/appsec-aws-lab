// Testes de segurança da API: cada cenário roda contra as duas versões.
// - na CORRIGIDA, a defesa precisa funcionar;
// - na VULNERÁVEL, o teste PROVA que a falha existe (se a falha sumir sem
//   querer, o laboratório deixa de demonstrar o achado e o teste avisa).
// Falhas de lógica como IDOR e resgate duplo não aparecem em scanner: só em
// teste com duas contas e com repetição, como estes.
import { createHmac } from "node:crypto";
import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";

process.env.SEGREDOS_FONTE = "env";
process.env.JWT_SECRET = "segredo-local-de-teste-nao-usar-em-producao";
process.env.WEBHOOK_SECRET = "webhook-local-de-teste-nao-usar-em-producao";

async function carregar(versao) {
  const { criarServidor } = await import(`../app/${versao}/src/server.mjs`);
  const { emitirToken } = await import(`../app/${versao}/src/auth.mjs`);
  return { criarServidor, emitirToken };
}

async function subir(versao) {
  const { criarServidor, emitirToken } = await carregar(versao);
  const logs = [];
  const registrar = (...partes) => logs.push(partes.map((p) => (typeof p === "string" ? p : JSON.stringify(p))).join(" "));
  const servidor = criarServidor({ log: { info: registrar, error: registrar, log: registrar } });
  await new Promise((ok) => servidor.listen(0, "127.0.0.1", ok));
  const base = `http://127.0.0.1:${servidor.address().port}`;
  const token = { a: await emitirToken("loja-a"), b: await emitirToken("loja-b") };

  async function chamar(metodo, caminho, { token: t, corpo, cabecalhos = {} } = {}) {
    const resposta = await fetch(base + caminho, {
      method: metodo,
      headers: { ...(t ? { authorization: `Bearer ${t}` } : {}), "content-type": "application/json", ...cabecalhos },
      body: corpo === undefined ? undefined : typeof corpo === "string" ? corpo : JSON.stringify(corpo),
    });
    const texto = await resposta.text();
    let json = null;
    try {
      json = JSON.parse(texto);
    } catch {}
    return { status: resposta.status, json, cabecalhos: resposta.headers };
  }
  return { chamar, token, logs, fechar: () => new Promise((ok) => servidor.close(ok)) };
}

/** Token com lojaId=loja-a e assinatura falsa (sem conhecer o segredo). */
function tokenForjado() {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  return `${b64({ alg: "HS256", typ: "JWT" })}.${b64({ lojaId: "loja-a", iss: "loja-api" })}.assinatura-falsa`;
}

const PEDIDO = { itens: [{ produtoId: "x-burguer", quantidade: 2 }], total: 0.01, telefone: "5586999991234" };

for (const versao of ["corrigido", "vulneravel"]) {
  const vulneravel = versao === "vulneravel";
  const titulo = vulneravel ? "versão vulnerável: prova de cada achado" : "versão corrigida: defesas";

  describe(titulo, () => {
    let api;
    before(async () => (api = await subir(versao)));
    after(() => api.fechar());

    test("IDOR: a loja B lê o cupom da loja A", async () => {
      const r = await api.chamar("GET", "/lojas/loja-a/cupons/BEMVINDO10", { token: api.token.b });
      if (vulneravel) assert.equal(r.json?.codigo, "BEMVINDO10", "a loja B deveria enxergar o cupom da loja A");
      else assert.equal(r.status, 403);
    });

    test("a própria loja lê o próprio cupom (controle positivo)", async () => {
      const r = await api.chamar("GET", "/lojas/loja-a/cupons/BEMVINDO10", { token: api.token.a });
      assert.equal(r.status, 200);
    });

    test("token com assinatura forjada", async () => {
      const r = await api.chamar("GET", "/lojas/loja-a/cupons/BEMVINDO10", { token: tokenForjado() });
      assert.equal(r.status, vulneravel ? 200 : 401);
    });

    test("total do pedido enviado pelo cliente", async () => {
      const r = await api.chamar("POST", "/pedidos", { token: api.token.a, corpo: PEDIDO });
      assert.equal(r.status, 201);
      assert.equal(r.json.total, vulneravel ? 0.01 : 65, "o total deve vir do catálogo (2 x R$ 32,50)");
    });

    test("telefone do cliente inteiro no log", async () => {
      api.logs.length = 0;
      await api.chamar("POST", "/pedidos", { token: api.token.a, corpo: PEDIDO });
      const vazou = api.logs.some((linha) => linha.includes(PEDIDO.telefone));
      assert.equal(vazou, vulneravel);
    });

    test("desconto enviado pelo cliente", async () => {
      const r = await api.chamar("POST", "/cupons/resgatar", {
        token: api.token.a,
        corpo: { codigo: "BEMVINDO10", pedidoId: "pedido-a1", valorDesconto: 80 },
      });
      assert.equal(r.status, 200);
      assert.equal(r.json.desconto, vulneravel ? 80 : 8, "o desconto deve ser 10% de R$ 80,00");
    });

    test("o mesmo cupom resgatado duas vezes", async () => {
      const r = await api.chamar("POST", "/cupons/resgatar", {
        token: api.token.a,
        corpo: { codigo: "BEMVINDO10", pedidoId: "pedido-a1", valorDesconto: 80 },
      });
      assert.equal(r.status, vulneravel ? 200 : 409);
    });

    test("a loja A usa o cupom da loja B", async () => {
      const r = await api.chamar("POST", "/cupons/resgatar", {
        token: api.token.a,
        corpo: { codigo: "VIP50", pedidoId: "pedido-a1", valorDesconto: 40 },
      });
      assert.equal(r.status, vulneravel ? 200 : 404);
    });

    test("webhook de pagamento sem assinatura", async () => {
      const r = await api.chamar("POST", "/webhooks/pagamento", { corpo: { lojaId: "loja-b", pedidoId: "pedido-b1" } });
      assert.equal(r.status, vulneravel ? 200 : 401);
    });

    test("webhook com assinatura HMAC válida (controle positivo)", { skip: vulneravel }, async () => {
      const corpo = JSON.stringify({ lojaId: "loja-b", pedidoId: "pedido-b1" });
      const assinatura = createHmac("sha256", process.env.WEBHOOK_SECRET).update(corpo).digest("hex");
      const r = await api.chamar("POST", "/webhooks/pagamento", { corpo, cabecalhos: { "x-assinatura": assinatura } });
      assert.equal(r.status, 200);
    });

    test("erro interno devolve detalhes ao cliente", async () => {
      const r = await api.chamar("POST", "/pedidos", { token: api.token.a, corpo: "{json quebrado" });
      assert.equal(Boolean(r.json?.stack), vulneravel);
      if (!vulneravel) assert.equal(r.status, 400);
    });

    test("cabeçalhos: versão anunciada e CORS aberto", async () => {
      const r = await api.chamar("GET", "/saude");
      if (vulneravel) {
        assert.match(r.cabecalhos.get("server") ?? "", /\d+\.\d+/);
        assert.equal(r.cabecalhos.get("access-control-allow-origin"), "*");
      } else {
        assert.equal(r.cabecalhos.get("server"), null);
        assert.equal(r.cabecalhos.get("access-control-allow-origin"), null);
        assert.equal(r.cabecalhos.get("x-content-type-options"), "nosniff");
        assert.equal(r.cabecalhos.get("cache-control"), "no-store");
      }
    });
  });
}
