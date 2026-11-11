// ⚠️ VERSÃO VULNERÁVEL DE PROPÓSITO — não use em produção.
// Falhas: segredo no código, biblioteca com CVE conhecida e token lido sem
// conferir a assinatura (qualquer pessoa forja um token de qualquer loja).
import jwt from "jsonwebtoken";

const JWT_SECRET = "Qm7vX2pL9rT4kW8nZ3cY6bH1dF5gJ0sA"; // segredo fictício plantado no código

export async function autenticar(authorization) {
  const token = (authorization || "").replace("Bearer ", "");
  const dados = jwt.decode(token);
  return dados && dados.lojaId ? { lojaId: dados.lojaId } : null;
}

export async function emitirToken(lojaId) {
  return jwt.sign({ lojaId }, JWT_SECRET);
}
