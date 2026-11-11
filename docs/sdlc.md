# Requisitos de segurança no ciclo de desenvolvimento

Cada etapa tem um entregável curto. A ideia é que segurança seja parte do "pronto", e não uma fase no fim.

## 1. Descoberta e design

- **Quando fazer threat model:** a feature mexe com autenticação, autorização, dinheiro, dados pessoais ou integração com terceiro. Use o formato de uma página de [threat-model.md](threat-model.md).
- **Requisitos que entram no card:**
  - de onde vem a identidade e o tenant;
  - quais valores o servidor calcula;
  - o que precisa ser idempotente;
  - que dado pessoal entra e por quanto tempo fica guardado.
- **Integração com parceiro:** definir como cada lado se autentica (HMAC, mTLS, OAuth) e o que fazer quando o parceiro estiver fora do ar.

## 2. Código

Regras da casa, que a esteira também cobra pelo Semgrep (`.semgrep/regras.yml`):

- a loja vem do token, nunca da URL nem do corpo;
- preço, total e desconto são calculados no servidor;
- token é verificado (assinatura, algoritmo e emissor);
- assinatura é comparada em tempo constante;
- log não leva objeto inteiro nem dado pessoal sem máscara;
- erro para o cliente é genérico;
- segredo nunca vai no código.

**Revisão com foco em segurança** é obrigatória nos PRs que tocam nas áreas do threat model. Checklist do revisor:

- [ ] Toda consulta filtra pelo tenant do token?
- [ ] Algum valor sensível vem do cliente?
- [ ] O que acontece com a requisição repetida ou simultânea?
- [ ] Entrada validada (tipo, tamanho, formato) antes de usar?
- [ ] Algum dado pessoal ou segredo vai para log, resposta ou mensagem de erro?
- [ ] Permissões IAM novas são as mínimas, com ARN específico?

## 3. Build (a esteira)

| Gate | Ferramenta | Bloqueia o merge quando |
|---|---|---|
| Segredos | gitleaks (código, infra e histórico) | qualquer segredo |
| SAST | Semgrep com as regras da casa | qualquer achado `ERROR` |
| Dependências | osv-scanner no lockfile | vulnerabilidade conhecida |
| IaC | Checkov no Terraform | qualquer falha sem `skip` justificado |
| Container | Hadolint e Trivy | regra do Dockerfile, ou CVE crítica com correção disponível |
| DAST | OWASP ZAP baseline | regra marcada como `FAIL` em `.zap/regras.tsv` |
| Testes de segurança | `node --test` | qualquer cenário de abuso que passe |

**Exceções:** só por `#checkov:skip`, `nosemgrep` ou allowlist, sempre com o motivo na mesma linha e aprovação de quem cuida de segurança. Uma exceção sem motivo é um achado.

## 4. Deploy

- Terraform com estado remoto criptografado e trava; `plan` revisado no PR antes do `apply`.
- Deploy por papel IAM da esteira (OIDC, sem chave de acesso fixa), com permissões só do que o Terraform gerencia.
- Segredos preenchidos fora da esteira ([segredos.md](segredos.md)).

## 5. Operação

- Logs de acesso, WAF e funções retidos por 365 dias, criptografados.
- Alertas: picos de 401/403 por loja, bloqueios do WAF, mensagens na fila de erro, falha do autorizador.
- Revisão trimestral de IAM (Access Analyzer) e de exceções da esteira.
- Achados de pentest externo e de varreduras entram no backlog com prazo pela severidade.

## Prazos de correção

| Severidade | Exemplo | Prazo |
|---|---|---|
| Crítica | IDOR em dado de cliente, segredo de produção exposto | 48 horas (mitigação em 24) |
| Alta | Falha de lógica com impacto financeiro, CVE crítica explorável | 7 dias |
| Média | Cabeçalho de segurança ausente, log com dado pessoal | 30 dias |
| Baixa | Hardening sem exploração conhecida | próximo ciclo |
