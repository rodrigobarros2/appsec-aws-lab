// Segredos vêm do AWS Secrets Manager, nunca do código nem de variável de
// ambiente com o valor. A Lambda recebe só o NOME do segredo (ex.: JWT_SECRET_ID)
// e a permissão IAM de ler aquele segredo específico.
//
// SEGREDOS_FONTE=env existe só para desenvolvimento e testes locais.

const CACHE_MS = 5 * 60 * 1000; // rotação entra em vigor em até 5 minutos
const cache = new Map();
let cliente;

export async function obterSegredo(nome) {
  if (process.env.SEGREDOS_FONTE === "env") {
    const valor = process.env[nome];
    if (!valor) throw new Error(`segredo ${nome} ausente no ambiente local`);
    return valor;
  }

  const id = process.env[`${nome}_ID`];
  if (!id) throw new Error(`variável ${nome}_ID não configurada`);

  const emCache = cache.get(id);
  if (emCache && emCache.expiraEm > Date.now()) return emCache.valor;

  const { SecretsManagerClient, GetSecretValueCommand } = await import("@aws-sdk/client-secrets-manager");
  cliente ??= new SecretsManagerClient({});
  const { SecretString } = await cliente.send(new GetSecretValueCommand({ SecretId: id }));
  if (!SecretString) throw new Error(`segredo ${id} sem valor`);

  cache.set(id, { valor: SecretString, expiraEm: Date.now() + CACHE_MS });
  return SecretString;
}
