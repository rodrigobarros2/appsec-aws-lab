# appsec-aws-lab

[![esteira-de-seguranca](https://github.com/rodrigobarros2/appsec-aws-lab/actions/workflows/esteira.yml/badge.svg)](https://github.com/rodrigobarros2/appsec-aws-lab/actions/workflows/esteira.yml)

Laboratório de **AppSec e DevSecOps** num SaaS serverless na AWS: um serviço de pedidos e cupons para restaurantes, com uma versão **vulnerável de propósito**, a versão **corrigida** e uma **esteira de segurança que prova que pega cada falha**.

A esteira não roda só na versão boa. Cada verificação roda nas duas: a corrigida precisa passar e a vulnerável precisa ser barrada. Se uma ferramenta deixar de pegar a falha plantada (por atualização, configuração errada ou regra desligada), o job falha. A própria esteira é testada.

> Dados 100% fictícios. Os segredos da versão vulnerável são inventados. Não aplique `infra/vulneravel` numa conta real.

## Arquitetura

```
Cliente ─▶ WAF ─▶ API Gateway (REST) ─▶ Autorizador JWT ─▶ Lambdas (Node.js 22) ─▶ DynamoDB
                                                              │                   └▶ SQS ─▶ Lambda ─▶ DynamoDB
Provedor de pagamento ─▶ WAF ─▶ API Gateway ─▶ Lambda webhook (HMAC)
                                         Secrets Manager + KMS ◀┘   S3 (relatórios) + KMS
```

Terraform com estado remoto no S3, criptografado com KMS, versionado e com trava (`use_lockfile`).

## A esteira

| Verificação | Ferramenta | Corrigido | Vulnerável |
|---|---|---|---|
| Testes de segurança (IDOR, token forjado, valores do cliente, resgate duplo, webhook, logs, erros, cabeçalhos) | `node --test` | defesas funcionam | 11 achados provados |
| Segredos no código e na infra | gitleaks | passa | barra |
| Segredos no histórico do Git | gitleaks | passa | — |
| SAST com regras da casa | Semgrep ([`.semgrep/regras.yml`](.semgrep/regras.yml)) | 0 achados | 9 achados |
| Dependências (SCA) | osv-scanner | passa | barra (`jsonwebtoken` 8.5.1) |
| Infraestrutura como código | Checkov | 237 aprovadas, 0 reprovadas, 24 exceções justificadas | 77 reprovadas |
| Dockerfile | Hadolint | passa | barra |
| Imagem do container | Trivy (CVEs críticas com correção) | passa | barra |
| DAST | OWASP ZAP baseline ([`.zap/regras.tsv`](.zap/regras.tsv)) | passa | barra |
| Terraform | `fmt` e `validate` | passa | passa |

**A esteira também se protege:**
- **Imagens:** as ferramentas rodam em imagens fixadas por versão **e digest**.
- **Actions:** fixadas por SHA.
- **Permissões:** o token do workflow só lê o repositório, e o checkout é feito sem credencial persistida.

**Bitbucket:** a mesma esteira está em [`bitbucket-pipelines.yml`](bitbucket-pipelines.yml), como gate da versão corrigida.

## O que foi corrigido

São 14 achados na aplicação, 9 na infraestrutura e 4 no container. A lista completa, com quem pega cada um e a referência OWASP/CWE, está em [docs/achados.md](docs/achados.md). Os principais:

- **IDOR entre lojas:** a loja passa a vir do token, e a chave do DynamoDB passa a ser `(lojaId, codigo)`.
- **Token aceito sem verificar a assinatura:** agora há um autorizador no API Gateway e `jwtVerify` com algoritmo, emissor e expiração.
- **Total e desconto enviados pelo cliente:** passam a ser calculados no servidor, e um schema JSON na borda recusa esses campos.
- **Cupom resgatado várias vezes:** a gravação no DynamoDB virou condicional.
- **Webhook sem assinatura:** HMAC obrigatório, comparado em tempo constante.
- **Segredos no código e na variável de ambiente da Lambda:** foram para o Secrets Manager com KMS.
- **IAM `*:*` com papel único:** um papel por função, com o mínimo necessário.
- **S3 público e dados sem criptografia:** chave KMS do cliente com rotação, bloqueio público e só HTTPS.
- **SSH aberto para a internet:** removido; o acesso administrativo passa a ser pelo SSM Session Manager.

O `diff` entre `app/vulneravel` e `app/corrigido`, e entre `infra/vulneravel` e `infra/corrigido`, mostra cada correção.

## Rodar localmente

Requisitos: Node.js 22 ou mais novo. Docker é opcional.

```bash
npm run instalar        # dependências das duas versões
npm test                # 23 testes: defesas da corrigida e prova dos achados na vulnerável

npm run vulneravel      # API vulnerável em http://localhost:8080
npm run corrigido       # API corrigida em http://127.0.0.1:8080 (uma por vez)
```

Para ver o IDOR, com a versão vulnerável no ar:

```bash
TOKEN_B=$(node -e "import('./app/vulneravel/src/auth.mjs').then(m=>m.emitirToken('loja-b')).then(console.log)")
curl -s -H "Authorization: Bearer $TOKEN_B" http://localhost:8080/lojas/loja-a/cupons/BEMVINDO10
# a loja B lê o cupom da loja A; na versão corrigida a resposta é 403
```

## Subir na AWS (versão corrigida)

Validado com `terraform validate`, Checkov e os testes. A aplicação real numa conta fica a seu critério e custo: WAF, KMS e Secrets Manager são cobrados.

```bash
# 1. bucket do estado (uma vez)
terraform -chdir=infra/estado-bootstrap init && terraform -chdir=infra/estado-bootstrap apply
terraform -chdir=infra/estado-bootstrap output -raw backend_hcl > infra/corrigido/backend.hcl

# 2. infraestrutura
npm ci --omit=dev --prefix app/corrigido
terraform -chdir=infra/corrigido init -backend-config=backend.hcl
terraform -chdir=infra/corrigido plan -out plano && terraform -chdir=infra/corrigido apply plano

# 3. valores dos segredos, fora do Terraform (ver docs/segredos.md)
```

## Documentos

- [Threat model](docs/threat-model.md): STRIDE do serviço, riscos aceitos e perguntas para features novas.
- [Requisitos de segurança no ciclo de desenvolvimento](docs/sdlc.md): do design à operação, gates da esteira e prazos de correção.
- [Gestão de segredos](docs/segredos.md): Secrets Manager, rotação, resposta a vazamento e HashiCorp Vault.
- [Programa de Security Champions](docs/security-champions.md): trilha de 6 encontros usando este laboratório.
- [Achados](docs/achados.md): antes e depois de cada falha.

## Uso responsável

Este repositório ensina a encontrar e corrigir falhas no **seu próprio** código e infraestrutura. Testar sistemas de terceiros sem autorização por escrito é crime no Brasil (Lei 12.737/2012, art. 154-A do Código Penal).

---

Rodrigo Barros · engenharia de software e segurança de aplicações · [rodrigobarros.tech](https://rodrigobarros.tech)
