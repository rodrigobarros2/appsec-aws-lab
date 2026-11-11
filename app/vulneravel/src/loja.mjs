// ⚠️ VERSÃO VULNERÁVEL DE PROPÓSITO — não use em produção.
// Falhas plantadas (compare com app/corrigido/src/loja.mjs):
// - IDOR: o cupom é buscado só pelo código, sem conferir a loja do token;
// - total do pedido e desconto vêm do cliente;
// - o mesmo cupom pode ser resgatado várias vezes;
// - o pedido inteiro (com telefone) vai para o log;
// - webhook aceita requisição sem assinatura e compara em tempo não constante.
import { createHmac } from "node:crypto";
import { resposta } from "./http.mjs";

const WEBHOOK_SECRET = "whsec_9Lk2Vt7Qx4Rm8Pz1Nw6Jc3Hb5Gd0Fs"; // segredo fictício plantado no código

export function criarLoja({ store, fila, log = console }) {
  return {
    async buscarCupom(auth, lojaIdDaUrl, codigo) {
      if (!auth) return resposta(401, { erro: "não autenticado" });
      const cupom = await store.buscarCupomPorCodigo(codigo);
      if (!cupom) return resposta(404, { erro: "não encontrado" });
      return resposta(200, cupom);
    },

    async criarPedido(auth, corpo) {
      if (!auth) return resposta(401, { erro: "não autenticado" });
      log.info("novo pedido " + JSON.stringify(corpo));
      const pedido = { lojaId: auth.lojaId, pedidoId: crypto.randomUUID(), total: corpo.total, telefone: corpo.telefone, pago: false };
      await fila.enviar(pedido);
      return resposta(201, { pedidoId: pedido.pedidoId, total: pedido.total });
    },

    async resgatarCupom(auth, corpo) {
      if (!auth) return resposta(401, { erro: "não autenticado" });
      const cupom = await store.buscarCupomPorCodigo(corpo.codigo);
      if (!cupom) return resposta(404, { erro: "não encontrado" });
      const pedido = await store.buscarPedido(auth.lojaId, corpo.pedidoId);
      if (!pedido) return resposta(404, { erro: "não encontrado" });
      await store.marcarCupomUsado(corpo.codigo);
      const desconto = corpo.valorDesconto;
      return resposta(200, { codigo: corpo.codigo, pedidoId: corpo.pedidoId, desconto, totalComDesconto: pedido.total - desconto });
    },

    async webhookPagamento(cabecalhos, corpoBruto) {
      const assinatura = cabecalhos["x-assinatura"];
      const esperada = createHmac("sha256", WEBHOOK_SECRET).update(corpoBruto).digest("hex");
      if (assinatura && assinatura != esperada) return resposta(401, { erro: "assinatura inválida" });
      const evento = JSON.parse(corpoBruto);
      await store.marcarPago(evento.lojaId, evento.pedidoId);
      return resposta(200, { ok: true });
    },
  };
}
