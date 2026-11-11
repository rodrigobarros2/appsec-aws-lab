// ⚠️ VERSÃO VULNERÁVEL DE PROPÓSITO — cupons indexados só pelo código (sem a loja).
import { dadosFicticios } from "./dados.mjs";

export function criarStoreMemoria() {
  const { cupons, pedidos } = dadosFicticios();
  const tabelaCupons = new Map(cupons.map((c) => [c.codigo, { ...c }]));
  const tabelaPedidos = new Map(pedidos.map((p) => [`${p.lojaId}#${p.pedidoId}`, { ...p }]));

  const store = {
    async buscarCupomPorCodigo(codigo) {
      return tabelaCupons.get(codigo) ?? null;
    },
    async marcarCupomUsado(codigo) {
      const cupom = tabelaCupons.get(codigo);
      if (cupom) cupom.usado = true;
    },
    async buscarPedido(lojaId, pedidoId) {
      return tabelaPedidos.get(`${lojaId}#${pedidoId}`) ?? null;
    },
    async salvarPedido(pedido) {
      tabelaPedidos.set(`${pedido.lojaId}#${pedido.pedidoId}`, { ...pedido });
    },
    async marcarPago(lojaId, pedidoId) {
      const pedido = tabelaPedidos.get(`${lojaId}#${pedidoId}`);
      if (pedido) pedido.pago = true;
    },
  };
  const fila = { enviar: (pedido) => store.salvarPedido(pedido) };
  return { store, fila };
}
