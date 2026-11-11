// Armazenamento real: DynamoDB (cupons, pedidos, catálogo) e SQS (fila de pedidos).
// O SDK v3 já vem no runtime Node.js da Lambda.
import { DynamoDBClient, ConditionalCheckFailedException } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand, PutCommand, UpdateCommand } from "@aws-sdk/lib-dynamodb";
import { SQSClient, SendMessageCommand } from "@aws-sdk/client-sqs";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const sqs = new SQSClient({});
const { TABELA_CUPONS, TABELA_PEDIDOS, TABELA_CATALOGO, FILA_PEDIDOS_URL } = process.env;

const condicionalFalhou = (erro) => erro instanceof ConditionalCheckFailedException;

export const store = {
  async catalogo(lojaId) {
    const { Item } = await ddb.send(new GetCommand({ TableName: TABELA_CATALOGO, Key: { lojaId } }));
    return Item?.precos ?? {};
  },
  async buscarCupom(lojaId, codigo) {
    const { Item } = await ddb.send(new GetCommand({ TableName: TABELA_CUPONS, Key: { lojaId, codigo } }));
    return Item ?? null;
  },
  async marcarCupomUsado(lojaId, codigo) {
    try {
      await ddb.send(new UpdateCommand({
        TableName: TABELA_CUPONS,
        Key: { lojaId, codigo },
        UpdateExpression: "SET usado = :sim",
        ConditionExpression: "attribute_exists(codigo) AND usado = :nao",
        ExpressionAttributeValues: { ":sim": true, ":nao": false },
      }));
      return true;
    } catch (erro) {
      if (condicionalFalhou(erro)) return false;
      throw erro;
    }
  },
  async buscarPedido(lojaId, pedidoId) {
    const { Item } = await ddb.send(new GetCommand({ TableName: TABELA_PEDIDOS, Key: { lojaId, pedidoId } }));
    return Item ?? null;
  },
  async salvarPedido(pedido) {
    try {
      // Idempotência: a SQS pode entregar a mesma mensagem mais de uma vez.
      await ddb.send(new PutCommand({
        TableName: TABELA_PEDIDOS,
        Item: pedido,
        ConditionExpression: "attribute_not_exists(pedidoId)",
      }));
    } catch (erro) {
      if (!condicionalFalhou(erro)) throw erro;
    }
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
