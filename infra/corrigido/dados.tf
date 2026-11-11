# DynamoDB: chave composta (lojaId + id). A loja faz parte da chave, então não
# existe consulta "só pelo código" que atravesse lojas (corrige o IDOR na raiz).
locals {
  tabelas = {
    cupons   = { chave = "lojaId", ordenacao = "codigo" }
    pedidos  = { chave = "lojaId", ordenacao = "pedidoId" }
    catalogo = { chave = "lojaId", ordenacao = null }
  }
}

resource "aws_dynamodb_table" "tabela" {
  for_each = local.tabelas

  name                        = "${local.prefixo}-${each.key}"
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = each.value.chave
  range_key                   = each.value.ordenacao
  deletion_protection_enabled = true

  attribute {
    name = each.value.chave
    type = "S"
  }

  dynamic "attribute" {
    for_each = each.value.ordenacao == null ? [] : [each.value.ordenacao]
    content {
      name = attribute.value
      type = "S"
    }
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.lab.arn
  }
}

# SQS: fila de pedidos criptografada com a chave do cliente e com fila de erro.
resource "aws_sqs_queue" "pedidos_dlq" {
  name                              = "${local.prefixo}-pedidos-dlq"
  message_retention_seconds         = 1209600
  kms_master_key_id                 = aws_kms_key.lab.arn
  kms_data_key_reuse_period_seconds = 300
}

resource "aws_sqs_queue" "pedidos" {
  name                              = "${local.prefixo}-pedidos"
  visibility_timeout_seconds        = 60
  kms_master_key_id                 = aws_kms_key.lab.arn
  kms_data_key_reuse_period_seconds = 300
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.pedidos_dlq.arn
    maxReceiveCount     = 5
  })
}

# Fila de erro das invocações assíncronas das Lambdas.
resource "aws_sqs_queue" "lambda_dlq" {
  name                              = "${local.prefixo}-lambda-dlq"
  message_retention_seconds         = 1209600
  kms_master_key_id                 = aws_kms_key.lab.arn
  kms_data_key_reuse_period_seconds = 300
}
