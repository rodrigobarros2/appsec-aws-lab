// Respostas HTTP com os cabeçalhos de segurança aplicados em todo lugar
// (servidor local e Lambda), para não depender de lembrar em cada rota.

export const CABECALHOS_SEGUROS = Object.freeze({
  "content-type": "application/json; charset=utf-8",
  "x-content-type-options": "nosniff",
  "cache-control": "no-store",
  "content-security-policy": "default-src 'none'; frame-ancestors 'none'",
  "x-frame-options": "DENY",
  "referrer-policy": "no-referrer",
  "strict-transport-security": "max-age=31536000; includeSubDomains",
});

export function resposta(status, corpo) {
  return { status, corpo };
}

export const naoAutenticado = () => resposta(401, { erro: "não autenticado" });
export const acessoNegado = () => resposta(403, { erro: "acesso negado" });
export const naoEncontrado = () => resposta(404, { erro: "não encontrado" });
export const invalido = (motivo) => resposta(400, { erro: motivo });
