// ⚠️ VERSÃO VULNERÁVEL DE PROPÓSITO — servidor local sem limite de corpo e que
// devolve o stack trace para o cliente.
import { createServer } from "node:http";
import { pathToFileURL } from "node:url";
import { autenticar } from "./auth.mjs";
import { CABECALHOS } from "./http.mjs";
import { criarLoja } from "./loja.mjs";
import { criarStoreMemoria } from "./store-memoria.mjs";

function lerCorpo(req) {
  return new Promise((resolve) => {
    let bruto = "";
    req.on("data", (parte) => (bruto += parte));
    req.on("end", () => resolve(bruto));
  });
}

export function criarServidor({ log = console } = {}) {
  const { store, fila } = criarStoreMemoria();
  const loja = criarLoja({ store, fila, log });

  return createServer(async (req, res) => {
    const enviar = ({ status, corpo }) => {
      res.writeHead(status, CABECALHOS);
      res.end(JSON.stringify(corpo));
    };
    try {
      const url = new URL(req.url, "http://localhost");
      const auth = await autenticar(req.headers.authorization);
      const bruto = req.method === "POST" ? await lerCorpo(req) : "";

      const cupom = /^\/lojas\/([\w-]+)\/cupons\/([\w-]+)$/.exec(url.pathname);
      if (req.method === "GET" && url.pathname === "/saude") return enviar({ status: 200, corpo: { ok: true } });
      if (req.method === "GET" && cupom) return enviar(await loja.buscarCupom(auth, cupom[1], cupom[2]));
      if (req.method === "POST" && url.pathname === "/pedidos") return enviar(await loja.criarPedido(auth, JSON.parse(bruto)));
      if (req.method === "POST" && url.pathname === "/cupons/resgatar") return enviar(await loja.resgatarCupom(auth, JSON.parse(bruto)));
      if (req.method === "POST" && url.pathname === "/webhooks/pagamento") {
        return enviar(await loja.webhookPagamento(req.headers, bruto));
      }
      return enviar({ status: 404, corpo: { erro: "não encontrado" } });
    } catch (erro) {
      return enviar({ status: 500, corpo: { erro: erro.message, stack: erro.stack } });
    }
  });
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const porta = Number(process.env.PORT ?? 8080);
  criarServidor().listen(porta, "0.0.0.0", () => console.log(`loja-api (vulnerável) em http://0.0.0.0:${porta}`));
}
