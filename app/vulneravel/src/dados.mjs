// Dados 100% fictícios: duas lojas, cada uma com seu catálogo, cupom e pedido.
export function dadosFicticios() {
  return {
    catalogos: {
      "loja-a": { "x-burguer": 32.5, "batata": 18, "refri": 8 },
      "loja-b": { "pizza-grande": 69.9, "suco": 12 },
    },
    cupons: [
      { lojaId: "loja-a", codigo: "BEMVINDO10", percentual: 10, usado: false },
      { lojaId: "loja-b", codigo: "VIP50", percentual: 50, usado: false },
    ],
    pedidos: [
      { lojaId: "loja-a", pedidoId: "pedido-a1", total: 80, telefone: "5586999990001", pago: false },
      { lojaId: "loja-b", pedidoId: "pedido-b1", total: 139.8, telefone: "5586999990002", pago: false },
    ],
  };
}
