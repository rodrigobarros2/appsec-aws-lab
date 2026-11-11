# Os segredos existem no Secrets Manager, mas o VALOR não passa pelo Terraform
# (senão iria para o state). Ele é gravado fora da esteira, uma vez:
#   aws secretsmanager put-secret-value --secret-id <nome> --secret-string file://valor.txt
# Rotação: ver docs/segredos.md.
resource "aws_secretsmanager_secret" "jwt" {
  #checkov:skip=CKV2_AWS_57:Rotação feita pelo runbook docs/segredos.md (troca com período de convivência das duas chaves).
  name                    = "${local.prefixo}/jwt"
  description             = "Chave HMAC que assina os tokens das lojas"
  kms_key_id              = aws_kms_key.lab.arn
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret" "webhook" {
  #checkov:skip=CKV2_AWS_57:Segredo compartilhado com o provedor de pagamento: rotação coordenada pelo runbook docs/segredos.md.
  name                    = "${local.prefixo}/webhook-pagamento"
  description             = "Segredo HMAC do webhook do provedor de pagamento"
  kms_key_id              = aws_kms_key.lab.arn
  recovery_window_in_days = 7
}
