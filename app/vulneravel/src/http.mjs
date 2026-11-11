// ⚠️ VERSÃO VULNERÁVEL DE PROPÓSITO — não use em produção.
// Falhas: anuncia versões no cabeçalho e libera CORS para qualquer origem.

export const CABECALHOS = {
  "content-type": "application/json",
  "server": "loja-api/0.1.3 (node 14.21.3)",
  "x-powered-by": "loja-api 0.1.3",
  "access-control-allow-origin": "*",
};

export function resposta(status, corpo) {
  return { status, corpo };
}
