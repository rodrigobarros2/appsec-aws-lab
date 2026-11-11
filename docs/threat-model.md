# Threat model: pedidos, cupons e pagamento

Modelo STRIDE do serviço do laboratório. Serve de exemplo do formato curto que eu uso em features novas: uma página, feito com quem vai construir, antes de escrever código.

## Fluxos e fronteiras de confiança

```
Cliente da loja ──HTTPS──▶ WAF ─▶ API Gateway ─▶ Autorizador (JWT) ─▶ Lambdas ─▶ DynamoDB / SQS
                                                                        │
Provedor de pagamento ──HTTPS + HMAC──▶ WAF ─▶ API Gateway ─▶ Lambda webhook
                                                                        │
Time de engenharia ──▶ Terraform (state no S3 + KMS) ──▶ conta AWS      └▶ Secrets Manager (KMS)
```

Fronteiras: internet → WAF/API Gateway; API Gateway → Lambda (contexto do autorizador); Lambda → dados; pipeline → conta AWS.

## Ameaças e mitigações

| STRIDE | Ameaça | Mitigação no laboratório | Como é verificada |
|---|---|---|---|
| **S** Falsificação | Token forjado ou alterado para se passar por outra loja | Autorizador TOKEN com `jwtVerify` (algoritmo e emissor fixos, expiração de 1 h) | Teste "token com assinatura forjada"; Semgrep `jwt-lido-sem-verificar` |
| **S** | Chamada falsa ao webhook marcando pedido como pago | HMAC-SHA256 obrigatório, comparação em tempo constante | Teste "webhook sem assinatura"; Semgrep `assinatura-comparada-sem-tempo-constante` |
| **T** Adulteração | Cliente manda o total, o preço ou o desconto | Valores calculados no servidor; schema da borda com `additionalProperties: false` | Testes de total e desconto; Semgrep `valor-monetario-vindo-do-cliente` |
| **T** | Resgate do mesmo cupom em paralelo | `UpdateItem` condicional (`usado = false`) | Teste "cupom resgatado duas vezes" |
| **T** | Mensagem repetida da fila duplica pedido | `PutItem` com `attribute_not_exists` e falha por item (`ReportBatchItemFailures`) | Revisão de código |
| **R** Repúdio | Loja nega ter feito uma operação | Log de acesso do API Gateway com `requestId`, IP e `lojaId`; logs retidos 365 dias e criptografados | Checkov (`CKV_AWS_76`, `CKV_AWS_158`, `CKV_AWS_338`) |
| **I** Vazamento | Loja B lê dados da loja A (IDOR/BOLA) | Loja vem do token; chave do DynamoDB começa pela loja | Teste "IDOR" com duas contas |
| **I** | Telefone do cliente nos logs | Log mínimo com máscara; `data_trace_enabled = false`; WAF redige o `Authorization` | Teste "telefone no log"; Semgrep `objeto-inteiro-no-log` |
| **I** | Segredo no código, na env da Lambda ou no state | Secrets Manager com KMS; só o nome do segredo na env; valor fora do Terraform | gitleaks; Semgrep `segredo-no-codigo` |
| **I** | Relatórios das lojas expostos | Bucket privado, KMS, só HTTPS | Checkov (`CKV_AWS_53..56`, `CKV_AWS_70`, `CKV_AWS_145`) |
| **D** Negação | Rajada de requisições ou corpo gigante | WAF com limite por IP; throttling no estágio; limite de 10 KB no corpo; concorrência reservada | Checkov (`CKV2_AWS_29`, `CKV_AWS_115`) |
| **E** Elevação | Função comprometida usa permissões de outra | Um papel IAM por função, ações e ARNs específicos | Checkov (`CKV_AWS_62/63/286..290`) |
| **E** | Pipeline ou ferramenta comprometida (supply chain) | Imagens fixadas por digest, actions por SHA, `permissions: contents: read`, checkout sem credencial | Revisão da esteira |

## Riscos aceitos

- **Lambdas fora de VPC**: só falam com serviços gerenciados por TLS; colocar em VPC exigiria NAT ou endpoints sem ganho real de isolamento aqui.
- **Sem assinatura de código (AWS Signer)**: entra no deploy de produção.
- **Rotação de segredos manual**, por runbook ([segredos.md](segredos.md)): o segredo do webhook é compartilhado com o provedor.

Cada risco aceito está como `#checkov:skip` com a justificativa no próprio Terraform, para a revisão enxergar.

## Perguntas para uma feature nova

1. Quem chama? Como a identidade chega até a regra de negócio, e de onde vem a loja/tenant?
2. Algum valor que mexe com dinheiro, permissão ou estado vem do cliente?
3. O que acontece se a mesma requisição chegar duas vezes, ou duas ao mesmo tempo?
4. Que dado pessoal entra, onde ele fica, quem lê e quando é apagado? Ele aparece em algum log?
5. Integra com terceiro? Como autenticamos a chamada dele e como ele autentica a nossa?
6. Qual o menor conjunto de permissões IAM para isso funcionar?
7. Como sabemos que alguém está abusando disso (métrica, log, alerta)?
