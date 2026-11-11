// ⚠️ VERSÃO VULNERÁVEL DE PROPÓSITO — sem autorizador no API Gateway: cada
// rota lê o token por conta própria (e aceita token forjado), e o evento
// inteiro vai para o log.
import { autenticar } from "./auth.mjs";
import { CABECALHOS } from "./http.mjs";
import { criarLoja } from "./loja.mjs";
import { fila, store } from "./store-aws.mjs";

const loja = criarLoja({ store, fila });

const paraApiGateway = ({ status, corpo }) => ({ statusCode: status, headers: CABECALHOS, body: JSON.stringify(corpo) });
const authDoEvento = (event) => autenticar(event.headers?.Authorization ?? event.headers?.authorization);

export async function cupom(event) {
  console.log(JSON.stringify(event));
  const { lojaId, codigo } = event.pathParameters ?? {};
  return paraApiGateway(await loja.buscarCupom(await authDoEvento(event), lojaId, codigo));
}

export async function pedidos(event) {
  return paraApiGateway(await loja.criarPedido(await authDoEvento(event), JSON.parse(event.body)));
}

export async function resgatar(event) {
  return paraApiGateway(await loja.resgatarCupom(await authDoEvento(event), JSON.parse(event.body)));
}

export async function webhook(event) {
  return paraApiGateway(await loja.webhookPagamento(event.headers ?? {}, event.body ?? ""));
}

export async function processarPedido(event) {
  for (const registro of event.Records ?? []) {
    await store.salvarPedido(JSON.parse(registro.body));
  }
}
