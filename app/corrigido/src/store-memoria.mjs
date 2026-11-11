// Armazenamento em memória para rodar localmente e nos testes.
// Chave composta (lojaId, codigo): o mesmo desenho da tabela no DynamoDB.
import { dadosFicticios } from "./dados.mjs";

export function criarStoreMemoria() {
  const { catalogos, cupons, pedidos } = dadosFicticios();
  const chave = (lojaId, id) => `${lojaId}#${id}`;
  const tabelaCupons = new Map(cupons.map((c) => [chave(c.lojaId, c.codigo), { ...c }]));
  const tabelaPedidos = new Map(pedidos.map((p) => [chave(p.lojaId, p.pedidoId), { ...p }]));

  const store = {
    async catalogo(lojaId) {
      return catalogos[lojaId] ?? {};
    },
    async buscarCupom(lojaId, codigo) {
      return tabelaCupons.get(chave(lojaId, codigo)) ?? null;
    },
    async marcarCupomUsado(lojaId, codigo) {
      const cupom = tabelaCupons.get(chave(lojaId, codigo));
      if (!cupom || cupom.usado) return false;
      cupom.usado = true;
      return true;
    },
    async buscarPedido(lojaId, pedidoId) {
      return tabelaPedidos.get(chave(lojaId, pedidoId)) ?? null;
    },
    async salvarPedido(pedido) {
      const k = chave(pedido.lojaId, pedido.pedidoId);
      if (!tabelaPedidos.has(k)) tabelaPedidos.set(k, { ...pedido });
    },
    async marcarPago(lojaId, pedidoId) {
      const pedido = tabelaPedidos.get(chave(lojaId, pedidoId));
      if (pedido) pedido.pago = true;
    },
  };
  const fila = { enviar: (pedido) => store.salvarPedido(pedido) };
  return { store, fila };
}
