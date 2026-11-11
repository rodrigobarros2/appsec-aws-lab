# Uma função e um papel IAM por responsabilidade: cada Lambda só pode tocar no
# que precisa (menor privilégio). Nenhum segredo vai em variável de ambiente:
# só o NOME do segredo.
locals {
  tabela = { for nome, t in aws_dynamodb_table.tabela : nome => t.arn }

  funcoes = {
    autorizador = {
      handler    = "src/lambda.autorizador"
      permissoes = [{ acoes = ["secretsmanager:GetSecretValue"], recursos = [aws_secretsmanager_secret.jwt.arn] }]
    }
    cupom = {
      handler    = "src/lambda.cupom"
      permissoes = [{ acoes = ["dynamodb:GetItem"], recursos = [local.tabela.cupons] }]
    }
    pedidos = {
      handler = "src/lambda.pedidos"
      permissoes = [
        { acoes = ["dynamodb:GetItem"], recursos = [local.tabela.catalogo] },
        { acoes = ["sqs:SendMessage"], recursos = [aws_sqs_queue.pedidos.arn] },
      ]
    }
    resgatar = {
      handler = "src/lambda.resgatar"
      permissoes = [
        { acoes = ["dynamodb:GetItem"], recursos = [local.tabela.pedidos, local.tabela.cupons] },
        { acoes = ["dynamodb:UpdateItem"], recursos = [local.tabela.cupons] },
      ]
    }
    webhook = {
      handler = "src/lambda.webhook"
      permissoes = [
        { acoes = ["secretsmanager:GetSecretValue"], recursos = [aws_secretsmanager_secret.webhook.arn] },
        { acoes = ["dynamodb:GetItem", "dynamodb:UpdateItem"], recursos = [local.tabela.pedidos] },
      ]
    }
    processar-pedido = {
      handler = "src/lambda.processarPedido"
      permissoes = [
        { acoes = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], recursos = [aws_sqs_queue.pedidos.arn] },
        { acoes = ["dynamodb:PutItem"], recursos = [local.tabela.pedidos] },
      ]
    }
  }

  ambiente_funcoes = {
    TABELA_CUPONS     = aws_dynamodb_table.tabela["cupons"].name
    TABELA_PEDIDOS    = aws_dynamodb_table.tabela["pedidos"].name
    TABELA_CATALOGO   = aws_dynamodb_table.tabela["catalogo"].name
    FILA_PEDIDOS_URL  = aws_sqs_queue.pedidos.url
    JWT_SECRET_ID     = aws_secretsmanager_secret.jwt.name
    WEBHOOK_SECRET_ID = aws_secretsmanager_secret.webhook.name
  }
}

data "archive_file" "codigo" {
  type        = "zip"
  source_dir  = "${path.module}/../../app/corrigido"
  output_path = "${path.module}/build/loja-api.zip"
  excludes    = ["Dockerfile", ".dockerignore"]
}

data "aws_iam_policy_document" "assumir_lambda" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.conta]
    }
  }
}

resource "aws_iam_role" "funcao" {
  for_each           = local.funcoes
  name               = "${local.prefixo}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.assumir_lambda.json
}

data "aws_iam_policy_document" "funcao" {
  for_each = local.funcoes

  dynamic "statement" {
    for_each = each.value.permissoes
    content {
      actions   = statement.value.acoes
      resources = statement.value.recursos
    }
  }

  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.funcao[each.key].arn}:*"]
  }

  statement {
    sid       = "ChaveDoLab"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.lab.arn]
  }

  statement {
    sid       = "FilaDeErro"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.lambda_dlq.arn]
  }

  statement {
    sid       = "XRay" # ações do X-Ray não aceitam restrição por recurso
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "funcao" {
  for_each = local.funcoes
  name     = "minimo-necessario"
  role     = aws_iam_role.funcao[each.key].id
  policy   = data.aws_iam_policy_document.funcao[each.key].json
}

resource "aws_cloudwatch_log_group" "funcao" {
  for_each          = local.funcoes
  name              = "/aws/lambda/${local.prefixo}-${each.key}"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.lab.arn
}

resource "aws_lambda_function" "funcao" {
  #checkov:skip=CKV_AWS_117:As funções só falam com serviços gerenciados da AWS (DynamoDB, SQS, Secrets Manager) por endpoint TLS; VPC exigiria NAT/endpoints sem ganho de isolamento aqui.
  #checkov:skip=CKV_AWS_272:Laboratório; em produção a assinatura de código entra com AWS Signer no pipeline de deploy.
  for_each = local.funcoes

  function_name                  = "${local.prefixo}-${each.key}"
  role                           = aws_iam_role.funcao[each.key].arn
  runtime                        = "nodejs22.x"
  architectures                  = ["arm64"]
  handler                        = each.value.handler
  filename                       = data.archive_file.codigo.output_path
  source_code_hash               = data.archive_file.codigo.output_base64sha256
  timeout                        = 10
  memory_size                    = 256
  reserved_concurrent_executions = 20
  kms_key_arn                    = aws_kms_key.lab.arn

  environment {
    variables = local.ambiente_funcoes
  }

  tracing_config {
    mode = "Active"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.funcao[each.key].name
  }

  depends_on = [aws_iam_role_policy.funcao]
}

resource "aws_lambda_event_source_mapping" "pedidos" {
  event_source_arn        = aws_sqs_queue.pedidos.arn
  function_name           = aws_lambda_function.funcao["processar-pedido"].arn
  batch_size              = 10
  function_response_types = ["ReportBatchItemFailures"]
}
