// Regras do serviço de pedidos e cupons (versão corrigida).
//
// Princípios aplicados:
// - a loja vem SEMPRE do token, nunca da URL ou do corpo;
// - valores monetários são calculados no servidor;
// - operações que mudam estado são idempotentes (resgate de cupom, pagamento);
// - dado pessoal não vai inteiro para o log.
import { createHmac, timingSafeEqual } from "node:crypto";
import { acessoNegado, invalido, naoAutenticado, naoEncontrado, resposta } from "./http.mjs";
import { obterSegredo } from "./segredos.mjs";

const MAX_ITENS = 50;

export function mascararTelefone(telefone) {
  const digitos = String(telefone ?? "").replace(/\D/g, "");
  return digitos.length < 6 ? "***" : `${digitos.slice(0, 2)}${"*".repeat(digitos.length - 6)}${digitos.slice(-4)}`;
}

const centavos = (valor) => Math.round(valor * 100) / 100;

export function criarLoja({ store, fila, log = console }) {
  return {
    async buscarCupom(auth, lojaIdDaUrl, codigo) {
      if (!auth) return naoAutenticado();
      if (auth.lojaId !== lojaIdDaUrl) return acessoNegado();
      const cupom = await store.buscarCupom(auth.lojaId, String(codigo));
      if (!cupom) return naoEncontrado();
      return resposta(200, { codigo: cupom.codigo, percentual: cupom.percentual, usado: cupom.usado });
    },

    async criarPedido(auth, corpo) {
      if (!auth) return naoAutenticado();
      const itens = Array.isArray(corpo?.itens) ? corpo.itens : null;
      if (!itens || itens.length === 0 || itens.length > MAX_ITENS) return invalido("itens inválidos");

      const catalogo = await store.catalogo(auth.lojaId);
      let total = 0;
      for (const item of itens) {
        const preco = catalogo[item?.produtoId];
        const quantidade = Number(item?.quantidade);
        if (preco === undefined || !Number.isInteger(quantidade) || quantidade < 1 || quantidade > 99) {
          return invalido("item fora do catálogo ou quantidade inválida");
        }
        total += preco * quantidade; // preço do catálogo, nunca do cliente
      }

      const telefone = String(corpo?.telefone ?? "").replace(/\D/g, "");
      if (telefone.length < 10 || telefone.length > 13) return invalido("telefone inválido");

      const pedido = { lojaId: auth.lojaId, pedidoId: crypto.randomUUID(), total: centavos(total), telefone, pago: false };
      await fila.enviar(pedido);
      log.info("pedido criado", { lojaId: pedido.lojaId, pedidoId: pedido.pedidoId, telefone: mascararTelefone(telefone) });
      return resposta(201, { pedidoId: pedido.pedidoId, total: pedido.total });
    },

    async resgatarCupom(auth, corpo) {
      if (!auth) return naoAutenticado();
      const codigo = String(corpo?.codigo ?? "");
      const pedidoId = String(corpo?.pedidoId ?? "");

      const pedido = await store.buscarPedido(auth.lojaId, pedidoId);
      if (!pedido) return naoEncontrado();
      const cupom = await store.buscarCupom(auth.lojaId, codigo);
      if (!cupom) return naoEncontrado();

      // Escrita condicional: só um resgate vence, mesmo com requisições simultâneas.
      const marcou = await store.marcarCupomUsado(auth.lojaId, codigo);
      if (!marcou) return resposta(409, { erro: "cupom já utilizado" });

      const desconto = centavos((pedido.total * cupom.percentual) / 100); // calculado no servidor
      return resposta(200, { codigo, pedidoId, desconto, totalComDesconto: centavos(pedido.total - desconto) });
    },

    async webhookPagamento(cabecalhos, corpoBruto) {
      const recebida = Buffer.from(String(cabecalhos["x-assinatura"] ?? ""), "utf8");
      const segredo = await obterSegredo("WEBHOOK_SECRET");
      const esperada = Buffer.from(createHmac("sha256", segredo).update(corpoBruto).digest("hex"), "utf8");
      if (recebida.length !== esperada.length || !timingSafeEqual(recebida, esperada)) return naoAutenticado();

      let evento;
      try {
        evento = JSON.parse(corpoBruto);
      } catch {
        return invalido("corpo inválido");
      }
      const pedido = await store.buscarPedido(String(evento.lojaId), String(evento.pedidoId));
      if (!pedido) return naoEncontrado();
      await store.marcarPago(pedido.lojaId, pedido.pedidoId); // idempotente: repetir não muda nada
      return resposta(200, { ok: true });
    },
  };
}
