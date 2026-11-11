// Handlers da Lambda atrás do API Gateway (REST, integração proxy).
// A autenticação acontece no autorizador; as rotas leem a loja do contexto
// que o autorizador devolveu, nunca do token cru nem da URL.
import { autenticar } from "./auth.mjs";
import { CABECALHOS_SEGUROS } from "./http.mjs";
import { criarLoja } from "./loja.mjs";
import { fila, store } from "./store-aws.mjs";

const loja = criarLoja({ store, fila });
const LIMITE_CORPO = 10 * 1024;

const paraApiGateway = ({ status, corpo }) => ({
  statusCode: status,
  headers: CABECALHOS_SEGUROS,
  body: JSON.stringify(corpo),
});

const lojaDoAutorizador = (event) => {
  const lojaId = event.requestContext?.authorizer?.lojaId;
  return typeof lojaId === "string" ? { lojaId } : null;
};

function lerCorpo(event) {
  const bruto = event.isBase64Encoded ? Buffer.from(event.body ?? "", "base64").toString("utf8") : event.body ?? "";
  if (Buffer.byteLength(bruto) > LIMITE_CORPO) return { erro: { status: 413, corpo: { erro: "corpo grande demais" } } };
  try {
    return { bruto, json: bruto ? JSON.parse(bruto) : {} };
  } catch {
    return { erro: { status: 400, corpo: { erro: "JSON inválido" } } };
  }
}

/** Autorizador TOKEN do API Gateway. */
export async function autorizador(event) {
  const auth = await autenticar(event.authorizationToken);
  if (!auth) throw new Error("Unauthorized"); // o API Gateway responde 401
  return {
    principalId: auth.lojaId,
    policyDocument: {
      Version: "2012-10-17",
      Statement: [{ Action: "execute-api:Invoke", Effect: "Allow", Resource: event.methodArn }],
    },
    context: { lojaId: auth.lojaId },
  };
}

export async function cupom(event) {
  const { lojaId, codigo } = event.pathParameters ?? {};
  return paraApiGateway(await loja.buscarCupom(lojaDoAutorizador(event), lojaId, codigo));
}

export async function pedidos(event) {
  const corpo = lerCorpo(event);
  if (corpo.erro) return paraApiGateway(corpo.erro);
  return paraApiGateway(await loja.criarPedido(lojaDoAutorizador(event), corpo.json));
}

export async function resgatar(event) {
  const corpo = lerCorpo(event);
  if (corpo.erro) return paraApiGateway(corpo.erro);
  return paraApiGateway(await loja.resgatarCupom(lojaDoAutorizador(event), corpo.json));
}

export async function webhook(event) {
  const corpo = lerCorpo(event);
  if (corpo.erro) return paraApiGateway(corpo.erro);
  const cabecalhos = Object.fromEntries(Object.entries(event.headers ?? {}).map(([k, v]) => [k.toLowerCase(), v]));
  return paraApiGateway(await loja.webhookPagamento(cabecalhos, corpo.bruto));
}

/** Consumidor da fila SQS: grava o pedido (idempotente) e reporta falhas por item. */
export async function processarPedido(event) {
  const falhas = [];
  for (const registro of event.Records ?? []) {
    try {
      await store.salvarPedido(JSON.parse(registro.body));
    } catch {
      falhas.push({ itemIdentifier: registro.messageId });
    }
  }
  return { batchItemFailures: falhas };
}
