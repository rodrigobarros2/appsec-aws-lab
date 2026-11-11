# Programa de Security Champions

Uma pessoa por squad que entende o básico de segurança, puxa o assunto no dia a dia e é o primeiro contato de quem cuida de AppSec. Ela não vira "a pessoa de segurança do time": continua desenvolvendo e ganha algumas horas por mês para o programa.

## Quem

- Voluntária, com o aval da liderança do squad.
- Curiosa e respeitada tecnicamente pelo time, e não necessariamente a pessoa mais sênior.
- Compromisso de cerca de 4 horas por mês: encontro quinzenal e revisão de PRs sensíveis do squad.

## Trilha inicial: 6 encontros de 1 hora

Cada encontro usa este laboratório. A pessoa encontra a falha na versão vulnerável, entende a correção e a regra da esteira que pega a falha.

| # | Tema | Exercício no laboratório | Leva para o squad |
|---|---|---|---|
| 1 | Controle de acesso e IDOR (BOLA) | Ler o cupom de outra loja com o token da sua | Checklist "toda consulta filtra pelo tenant do token?" |
| 2 | Autenticação e tokens | Forjar um token na versão vulnerável e ver o autorizador barrar na corrigida | Regra de verificar algoritmo, emissor e expiração |
| 3 | Lógica de negócio e dinheiro | Mandar desconto e total pelo corpo; resgatar o mesmo cupom duas vezes | Perguntas de idempotência e de valor calculado no servidor |
| 4 | Segredos e infraestrutura | Achar segredo no código e na env da Lambda; ler o Checkov da infra vulnerável | Rotina de segredo e revisão de `plan` do Terraform |
| 5 | Integrações e webhooks | Chamar o webhook sem assinatura; entender HMAC e tempo constante | Padrão de autenticação de parceiro |
| 6 | Dados pessoais e LGPD | Achar o telefone no log; mascarar | Revisão dos logs do squad |

Depois da trilha, um encontro por mês com um achado real e anonimizado da empresa: o que aconteceu, como foi corrigido e qual regra nova entrou na esteira.

## Rituais

- **Threat model de 30 minutos** nas features da lista de [sdlc.md](sdlc.md), com o champion facilitando.
- **Revisão de segurança** dos PRs sensíveis do squad, com escalonamento para AppSec quando houver dúvida.
- **Triagem da esteira:** o champion ajuda o time a corrigir ou justificar os achados, para ninguém desligar o gate.

## Como medir

- Tempo médio de correção por severidade, por squad.
- Percentual de features da lista com threat model feito antes do código.
- Exceções da esteira sem justificativa (meta: zero).
- Achados de pentest externo que a esteira ou o time já deveriam ter pego (meta: cair a cada ciclo).
- Participação nos encontros e PRs revisados pelos champions.

## Reconhecimento

Crédito público nas apresentações de engenharia, prioridade em treinamentos e certificações de segurança, e a participação no programa contando na avaliação de desempenho.
