// Servidor HTTP local (sem AWS) para testes, DAST e demonstração.
import { createServer } from "node:http";
import { pathToFileURL } from "node:url";
import { autenticar } from "./auth.mjs";
import { CABECALHOS_SEGUROS } from "./http.mjs";
import { criarLoja } from "./loja.mjs";
import { criarStoreMemoria } from "./store-memoria.mjs";

const LIMITE_CORPO = 10 * 1024;

function lerCorpo(req) {
  return new Promise((resolve, reject) => {
    let tamanho = 0;
    const partes = [];
    req.on("data", (parte) => {
      tamanho += parte.length;
      if (tamanho > LIMITE_CORPO) {
        reject(Object.assign(new Error("corpo grande demais"), { status: 413 }));
        req.destroy();
        return;
      }
      partes.push(parte);
    });
    req.on("end", () => resolve(Buffer.concat(partes).toString("utf8")));
    req.on("error", reject);
  });
}

export function criarServidor({ log = console } = {}) {
  const { store, fila } = criarStoreMemoria();
  const loja = criarLoja({ store, fila, log });

  return createServer(async (req, res) => {
    const enviar = ({ status, corpo }) => {
      res.writeHead(status, CABECALHOS_SEGUROS);
      res.end(JSON.stringify(corpo));
    };
    try {
      const url = new URL(req.url, "http://localhost");
      const auth = await autenticar(req.headers.authorization);
      const bruto = req.method === "POST" ? await lerCorpo(req) : "";
      const json = () => {
        try {
          return bruto ? JSON.parse(bruto) : {};
        } catch {
          return null;
        }
      };

      const cupom = /^\/lojas\/([\w-]+)\/cupons\/([\w-]+)$/.exec(url.pathname);
      if (req.method === "GET" && url.pathname === "/saude") return enviar({ status: 200, corpo: { ok: true } });
      if (req.method === "GET" && cupom) return enviar(await loja.buscarCupom(auth, cupom[1], cupom[2]));
      if (req.method === "POST" && url.pathname === "/pedidos") return enviar(await loja.criarPedido(auth, json()));
      if (req.method === "POST" && url.pathname === "/cupons/resgatar") return enviar(await loja.resgatarCupom(auth, json()));
      if (req.method === "POST" && url.pathname === "/webhooks/pagamento") {
        return enviar(await loja.webhookPagamento(req.headers, bruto));
      }
      return enviar({ status: 404, corpo: { erro: "não encontrado" } });
    } catch (erro) {
      // Mensagem genérica para o cliente; detalhe só no log interno.
      log.error("erro na requisição", { mensagem: erro.message });
      return enviar({ status: erro.status ?? 500, corpo: { erro: erro.status ? erro.message : "erro interno" } });
    }
  });
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const porta = Number(process.env.PORT ?? 8080);
  const host = process.env.HOST ?? "127.0.0.1";
  criarServidor().listen(porta, host, () => console.info(`loja-api (corrigida) em http://${host}:${porta}`));
}
