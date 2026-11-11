# Achados: antes e depois

Cada falha plantada na versão vulnerável, quem a pega e como foi corrigida. As linhas "Teste" se referem a `testes/seguranca.test.mjs`, que roda a mesma situação de abuso nas duas versões.

## Aplicação

| # | Achado | Severidade | Quem pega | Correção | Referência |
|---|---|---|---|---|---|
| A1 | **IDOR:** a loja B lê o cupom da loja A trocando a URL | Crítica | Teste com duas contas | Loja vem do token; chave do DynamoDB `(lojaId, codigo)`; 403 se a URL não bate com o token | OWASP API1:2023 (BOLA) |
| A2 | **Token lido sem verificar a assinatura** (`jwt.decode`): qualquer um vira qualquer loja | Crítica | Semgrep `jwt-lido-sem-verificar` + teste de token forjado | `jwtVerify` (jose) com algoritmo, emissor e expiração; autorizador no API Gateway | API2:2023, CWE-347 |
| A3 | **Segredos no código** (chave do JWT e do webhook) | Crítica | gitleaks + Semgrep `segredo-no-codigo` | Secrets Manager com KMS; só o nome do segredo na configuração | CWE-798 |
| A4 | **Biblioteca com vulnerabilidade conhecida** (`jsonwebtoken` 8.5.1) | Alta | osv-scanner | Troca por `jose` atual | OWASP A06:2021 |
| A5 | **Total do pedido vem do cliente** | Alta | Semgrep `valor-monetario-vindo-do-cliente` + teste | Total calculado pelo catálogo; schema na borda recusa o campo | API6:2023, CWE-602 |
| A6 | **Desconto vem do cliente** | Alta | Semgrep + teste | Desconto = percentual do cupom × total do pedido, no servidor | API6:2023 |
| A7 | **Mesmo cupom resgatado várias vezes** (inclusive em paralelo) | Alta | Teste de repetição | `UpdateItem` condicional (`usado = false`): só um vence | CWE-367 |
| A8 | **Cupom de outra loja aceito no resgate** | Alta | Teste | Busca do cupom pela loja do token | API1:2023 |
| A9 | **Webhook aceita chamada sem assinatura** e compara com `!=` | Crítica | Semgrep `assinatura-comparada-sem-tempo-constante` + teste | HMAC obrigatório com `timingSafeEqual` | CWE-345, CWE-208 |
| A10 | **Telefone do cliente e evento inteiro no log** | Média (LGPD) | Semgrep `objeto-inteiro-no-log` + teste | Log só com ids e telefone mascarado; `data_trace_enabled = false`; WAF redige o `Authorization` | CWE-532 |
| A11 | **Stack trace na resposta de erro** | Média | Semgrep `stack-trace-na-resposta` + teste | Mensagem genérica ao cliente; detalhe só no log | CWE-209 |
| A12 | **Cabeçalhos:** versão anunciada no `Server` e `X-Powered-By`, CORS `*`, sem `nosniff` e CSP | Média | OWASP ZAP baseline + teste | Cabeçalhos seguros em toda resposta; sem CORS (API não é chamada por navegador de terceiros) | OWASP A05:2021 |
| A13 | **Sem limite de tamanho do corpo** | Média | Revisão | Limite de 10 KB no servidor e na Lambda; schema na borda | CWE-770 |
| A14 | **Mensagem repetida da fila duplica o pedido** | Média | Revisão | `PutItem` com `attribute_not_exists`; falha reportada por mensagem | Idempotência |

## Infraestrutura (Terraform)

| # | Achado | Severidade | Quem pega | Correção |
|---|---|---|---|---|
| I1 | **IAM `Action: *` e `Resource: *`**, um papel para todas as funções | Crítica | Checkov `CKV_AWS_62`, `CKV_AWS_63`, `CKV_AWS_286` a `290`, `CKV2_AWS_40` | Um papel por função, só as ações e ARNs necessários |
| I2 | **Bucket S3 público**, sem criptografia, versionamento e ciclo de vida | Crítica | Checkov `CKV_AWS_53` a `56`, `CKV_AWS_70`, `CKV_AWS_145`, `CKV_AWS_21`, `CKV2_AWS_6`, `CKV2_AWS_61` | Bloqueio público, KMS, versionamento, só HTTPS, ACLs desligadas |
| I3 | **Segredos em texto claro na variável de ambiente da Lambda** | Crítica | gitleaks na pasta `infra/` (o Checkov não pegou) | Secrets Manager; a env leva só o nome |
| I4 | **DynamoDB sem chave própria e sem PITR**; cupons sem a loja na chave | Alta | Checkov `CKV_AWS_119`, `CKV_AWS_28` | Chave KMS do cliente com rotação, PITR, proteção contra exclusão, chave composta |
| I5 | **Fila SQS sem criptografia e sem fila de erro** | Média | Checkov `CKV_AWS_27` | KMS e DLQ com `maxReceiveCount = 5` |
| I6 | **API sem autorizador, WAF, validação, logs e throttling** | Crítica | Checkov `CKV_AWS_59`, `CKV2_AWS_29`, `CKV2_AWS_53`, `CKV_AWS_76`, `CKV2_AWS_4`, `CKV_AWS_73` | Autorizador TOKEN, WAF (regras gerenciadas, limite por IP, IPs anônimos), schema JSON, logs com KMS, throttling e X-Ray |
| I7 | **Lambda em runtime sem suporte** (`nodejs14.x`), sem tracing, fila de erro e limite de concorrência | Alta | Checkov `CKV_AWS_363`, `CKV_AWS_50`, `CKV_AWS_116`, `CKV_AWS_115`, `CKV_AWS_173` | `nodejs22.x` em arm64, X-Ray, DLQ, concorrência reservada, env criptografada com KMS |
| I8 | **Security Group com SSH aberto para a internet** | Crítica | Checkov `CKV_AWS_24`, `CKV_AWS_382`, `CKV_AWS_23` | Removido: acesso administrativo via SSM Session Manager, sem porta aberta |
| I9 | **Estado do Terraform local**, sem criptografia, versionamento ou trava | Alta | Revisão | Backend S3 com KMS, versionamento, só HTTPS e `use_lockfile` (bootstrap em `infra/estado-bootstrap`) |

**Riscos aceitos** na versão corrigida: 24 exceções do Checkov, cada uma com `#checkov:skip` e o motivo na mesma linha. Por exemplo, a Lambda fica fora da VPC, o cache da API fica desligado porque as respostas dependem da loja autenticada, e a rotação de segredos é feita por runbook.

## Container

| # | Achado | Quem pega | Correção |
|---|---|---|---|
| C1 | Imagem `node:14` (sem suporte, sem versão fixa), com CVEs críticas | Trivy | `node:22` Alpine fixado por versão e digest |
| C2 | `ADD .` copia tudo, inclusive arquivos locais | Hadolint `DL3020` | `COPY` só do necessário, com `.dockerignore` |
| C3 | `CMD` em forma de shell (sinais não chegam ao processo) | Hadolint `DL3025` | `CMD ["node", "src/server.mjs"]` |
| C4 | Roda como root e leva npm na imagem final | Revisão | Build em dois estágios, `USER 1000:1000`, sem npm e corepack na imagem final |

### Um achado real durante a construção

Na primeira versão, a imagem corrigida usava `node:22.21.1-alpine3.22`. Na primeira execução, o Trivy **barrou a própria versão corrigida**: a base trazia 2 CVEs críticas no OpenSSL (`libcrypto3` e `libssl3`, CVE-2026-31789), já corrigidas na 3.5.6. A troca para `node:22.23.5-alpine3.24` resolveu. Isso mostra por que a imagem fixada por digest precisa de um scanner no gate: fixar garante reprodutibilidade, mas não garante atualização. Em produção, o Dependabot (ou o Renovate) abre o PR de atualização do digest, e a esteira valida.

## O que nenhuma ferramenta pegou sozinha

IDOR (A1, A8), resgate duplo (A7) e a lógica do desconto (A6) só aparecem com **teste que pensa como atacante**: duas contas, repetição e valores fora do esperado. A esteira automatiza esse teste, mas alguém precisou pensar nele primeiro. É por isso que revisão de código e threat model continuam necessários mesmo com todas as ferramentas ligadas.
