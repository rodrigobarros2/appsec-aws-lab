# Uma chave KMS gerenciada pelo cliente para dados, fila, segredos, logs e
# variáveis das Lambdas, com rotação anual automática.
resource "aws_kms_key" "lab" {
  description             = "appsec-aws-lab: dados, fila, segredos e logs"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms.json
}

resource "aws_kms_alias" "lab" {
  name          = "alias/${local.prefixo}"
  target_key_id = aws_kms_key.lab.key_id
}

# Em key policy, Resource "*" significa "esta chave": não dá para restringir mais.
data "aws_iam_policy_document" "kms" {
  #checkov:skip=CKV_AWS_109:Key policy: Resource "*" se refere à própria chave; administração só pela conta.
  #checkov:skip=CKV_AWS_111:Key policy: Resource "*" se refere à própria chave.
  #checkov:skip=CKV_AWS_356:Key policy: Resource "*" se refere à própria chave.
  statement {
    sid       = "AdministracaoPelaConta"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = [local.raiz_arn]
    }
  }

  statement {
    sid       = "CloudWatchLogs"
    actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${var.regiao}.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${local.particao}:logs:${var.regiao}:${local.conta}:log-group:*"]
    }
  }
}
