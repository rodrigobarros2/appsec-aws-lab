#!/usr/bin/env bash
# Roda uma verificação e confere o resultado ESPERADO para cada versão:
#   corrigido  -> a ferramenta tem que aprovar (código 0);
#   vulneravel -> a ferramenta tem que barrar com achados (código 1).
# Qualquer outro código é erro da própria ferramenta e reprova o job: assim um
# scanner quebrado nunca vira "achou a falha" por engano.
#
# Uso: scripts/esperar.sh <corrigido|vulneravel> "<nome da verificação>" comando [args...]
set -uo pipefail

alvo="$1"
nome="$2"
shift 2

"$@"
codigo=$?

case "$alvo:$codigo" in
  corrigido:0)  echo "✅ ${nome}: versão corrigida aprovada" ;;
  vulneravel:1) echo "✅ ${nome}: a esteira barrou a versão vulnerável, como esperado" ;;
  vulneravel:0) echo "❌ ${nome}: a versão vulnerável PASSOU — a verificação deixou de pegar a falha plantada"; exit 1 ;;
  corrigido:1)  echo "❌ ${nome}: a versão corrigida foi reprovada"; exit 1 ;;
  *)            echo "❌ ${nome}: erro da ferramenta (código ${codigo})"; exit 1 ;;
esac
