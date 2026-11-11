// ⚠️ VERSÃO VULNERÁVEL DE PROPÓSITO — tabela de cupons com chave só no código
// e gravações sem condição (resgate duplo e mensagem repetida da fila passam).
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand, PutCommand, UpdateCommand } from "@aws-sdk/lib-dynamodb";
import { SQSClient, SendMessageCommand } from "@aws-sdk/client-sqs";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const sqs = new SQSClient({});
const { TABELA_CUPONS, TABELA_PEDIDOS, FILA_PEDIDOS_URL } = process.env;

export const store = {
  async buscarCupomPorCodigo(codigo) {
    const { Item } = await ddb.send(new GetCommand({ TableName: TABELA_CUPONS, Key: { codigo } }));
    return Item ?? null;
  },
  async marcarCupomUsado(codigo) {
    await ddb.send(new UpdateCommand({
      TableName: TABELA_CUPONS,
      Key: { codigo },
      UpdateExpression: "SET usado = :sim",
      ExpressionAttributeValues: { ":sim": true },
    }));
  },
  async buscarPedido(lojaId, pedidoId) {
    const { Item } = await ddb.send(new GetCommand({ TableName: TABELA_PEDIDOS, Key: { lojaId, pedidoId } }));
    return Item ?? null;
  },
  async salvarPedido(pedido) {
    await ddb.send(new PutCommand({ TableName: TABELA_PEDIDOS, Item: pedido }));
  },
  async marcarPago(lojaId, pedidoId) {
    await ddb.send(new UpdateCommand({
      TableName: TABELA_PEDIDOS,
      Key: { lojaId, pedidoId },
      UpdateExpression: "SET pago = :sim",
      ExpressionAttributeValues: { ":sim": true },
    }));
  },
};

export const fila = {
  async enviar(pedido) {
    await sqs.send(new SendMessageCommand({ QueueUrl: FILA_PEDIDOS_URL, MessageBody: JSON.stringify(pedido) }));
  },
};
