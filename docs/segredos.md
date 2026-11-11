# Gestão de segredos

## Regras

1. **Segredo não entra no código, nem em variável de ambiente com o valor, nem no state do Terraform.** A Lambda recebe só o nome do segredo (`JWT_SECRET_ID`) e uma permissão IAM para ler aquele segredo específico.
2. **Cada segredo tem dono, finalidade e rotina de rotação** documentados.
3. **Segredo vazado é revogado primeiro.** Limpar o histórico do Git vem depois e não "desvaza" nada: quem clonou já tem o valor.

## Como funciona no laboratório

- O Terraform cria os segredos no Secrets Manager, criptografados com a chave KMS do projeto (`infra/corrigido/segredos.tf`), **sem valor**.
- O valor é gravado uma vez, fora da esteira, por quem tem o papel de administrador:

  ```bash
  openssl rand -base64 48 > valor.txt
  aws secretsmanager put-secret-value --secret-id loja-lab/jwt --secret-string file://valor.txt
  shred -u valor.txt
  ```

- A função lê com `GetSecretValue` e guarda em cache por 5 minutos (`app/corrigido/src/segredos.mjs`). Uma troca de valor entra em vigor em até 5 minutos sem novo deploy.
- Em desenvolvimento, `SEGREDOS_FONTE=env` lê da variável de ambiente local. Esse modo não existe na Lambda, porque o Terraform não define essa variável.

## Rotação

### Chave dos tokens (JWT)

O laboratório usa uma chave por vez, e os tokens duram 1 hora. Trocar o valor invalida as sessões abertas em até 5 minutos. Para trocar **sem derrubar ninguém**, o passo seguinte é aceitar duas chaves por um período:

1. Gravar a nova chave como `AWSPENDING` e publicar as duas com identificador (`kid`).
2. Emitir tokens só com a nova; validar com qualquer uma das duas.
3. Depois de 1 hora (a validade do token), promover a nova para `AWSCURRENT` e remover a antiga.

### Segredo do webhook de pagamento

É compartilhado com o provedor, então a troca é coordenada:

1. Gerar o novo segredo no painel do provedor (a maioria permite dois ativos ao mesmo tempo).
2. Gravar no Secrets Manager.
3. Aguardar 5 minutos (cache) e conferir que os webhooks seguem com 200.
4. Desativar o segredo antigo no provedor.

### Periodicidade

| Segredo | Rotina | Imediata quando |
|---|---|---|
| Chave JWT | a cada 90 dias | suspeita de vazamento ou saída de alguém com acesso |
| Webhook do pagamento | a cada 180 dias | idem, ou incidente no provedor |
| Chaves de API de terceiros | conforme o provedor, no máximo anual | idem |

## Achado de segredo no repositório

1. **Revogar ou rotacionar** o segredo na origem (provedor, AWS, banco).
2. Conferir no CloudTrail e nos logs do provedor se houve uso indevido entre o commit e a revogação.
3. Mover o valor novo para o Secrets Manager e corrigir o código.
4. Só então reescrever o histórico (`git filter-repo`) se o repositório for público ou compartilhado, e pedir aos times que clonem de novo.
5. Registrar o caso e, se for um padrão novo, virar regra na esteira (gitleaks ou Semgrep).

## HashiCorp Vault

Em empresas com Vault, o mesmo desenho vale trocando a fonte:

- **KV v2** para segredos estáticos, com versionamento e `check-and-set`.
- **Método de autenticação AWS IAM** para a Lambda: ela se autentica com o próprio papel IAM, sem token fixo. A **Vault Lambda Extension** busca o segredo e entrega num arquivo local.
- **Segredos dinâmicos** para banco relacional: o Vault cria um usuário com validade curta por execução. É o ganho real sobre segredo estático.

Para testar localmente:

```bash
docker run --rm -d --name vault -p 8200:8200 -e VAULT_DEV_ROOT_TOKEN_ID=dev hashicorp/vault:1.20
export VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=dev
vault kv put secret/loja/jwt valor="$(openssl rand -base64 48)"
vault kv get -field=valor secret/loja/jwt
```

O código do laboratório lê do Secrets Manager. Para usar o Vault, basta trocar a implementação de `obterSegredo`, sem mexer nas regras de negócio.
