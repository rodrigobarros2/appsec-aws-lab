# ⚠️ INFRAESTRUTURA VULNERÁVEL DE PROPÓSITO — não aplique numa conta real.
# É o "antes" do laboratório: cada bloco tem uma falha comum em SaaS na AWS.
# O "depois" está em ../corrigido.
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
  # FALHA: estado local, sem criptografia, sem versionamento e sem trava.
}

provider "aws" {
  region = "sa-east-1"
}

# FALHA: bucket de relatórios público, sem criptografia e sem versionamento.
resource "aws_s3_bucket" "relatorios" {
  bucket = "loja-relatorios-lab"
}

resource "aws_s3_bucket_public_access_block" "relatorios" {
  bucket                  = aws_s3_bucket.relatorios.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "relatorios" {
  bucket = aws_s3_bucket.relatorios.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "LeituraPublica"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.relatorios.arn}/*"
    }]
  })
}

# FALHA: cupons com chave só no código (sem a loja), sem PITR e sem chave própria.
resource "aws_dynamodb_table" "cupons" {
  name         = "loja-cupons"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "codigo"
  attribute {
    name = "codigo"
    type = "S"
  }
}

resource "aws_dynamodb_table" "pedidos" {
  name         = "loja-pedidos"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "lojaId"
  range_key    = "pedidoId"
  attribute {
    name = "lojaId"
    type = "S"
  }
  attribute {
    name = "pedidoId"
    type = "S"
  }
}

# FALHA: fila sem criptografia e sem fila de erro (mensagem envenenada fica em loop).
resource "aws_sqs_queue" "pedidos" {
  name                    = "loja-pedidos"
  sqs_managed_sse_enabled = false
}

# FALHA: um papel só para todas as funções, com permissão total na conta.
resource "aws_iam_role" "lambda" {
  name = "loja-lambda"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "tudo"
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "*", Resource = "*" }]
  })
}

data "archive_file" "codigo" {
  type        = "zip"
  source_dir  = "${path.module}/../../app/vulneravel"
  output_path = "${path.module}/build/loja-api.zip"
}

# FALHA: segredos em texto claro na variável de ambiente (aparecem no console,
# na API GetFunctionConfiguration e no state), sem tracing, sem fila de erro e
# sem limite de concorrência.
resource "aws_lambda_function" "funcao" {
  for_each = toset(["cupom", "pedidos", "resgatar", "webhook", "processarPedido"])

  function_name    = "loja-${each.key}"
  role             = aws_iam_role.lambda.arn
  runtime          = "nodejs14.x"
  handler          = "src/lambda.${each.key}"
  filename         = data.archive_file.codigo.output_path
  source_code_hash = data.archive_file.codigo.output_base64sha256

  environment {
    variables = {
      TABELA_CUPONS    = aws_dynamodb_table.cupons.name
      TABELA_PEDIDOS   = aws_dynamodb_table.pedidos.name
      FILA_PEDIDOS_URL = aws_sqs_queue.pedidos.url
      JWT_SECRET       = "Qm7vX2pL9rT4kW8nZ3cY6bH1dF5gJ0sA"
      WEBHOOK_SECRET   = "whsec_9Lk2Vt7Qx4Rm8Pz1Nw6Jc3Hb5Gd0Fs"
    }
  }
}

# FALHA: API sem autorizador, sem WAF, sem logs de acesso e sem throttling.
resource "aws_api_gateway_rest_api" "loja" {
  name = "loja-api"
}

resource "aws_api_gateway_resource" "pedidos" {
  rest_api_id = aws_api_gateway_rest_api.loja.id
  parent_id   = aws_api_gateway_rest_api.loja.root_resource_id
  path_part   = "pedidos"
}

resource "aws_api_gateway_method" "pedidos" {
  rest_api_id   = aws_api_gateway_rest_api.loja.id
  resource_id   = aws_api_gateway_resource.pedidos.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "pedidos" {
  rest_api_id             = aws_api_gateway_rest_api.loja.id
  resource_id             = aws_api_gateway_resource.pedidos.id
  http_method             = aws_api_gateway_method.pedidos.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.funcao["pedidos"].invoke_arn
}

resource "aws_api_gateway_deployment" "loja" {
  rest_api_id = aws_api_gateway_rest_api.loja.id
  depends_on  = [aws_api_gateway_integration.pedidos]
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.loja.id
  deployment_id = aws_api_gateway_deployment.loja.id
  stage_name    = "prod"
}

# FALHA: Security Group com SSH aberto para a internet (acesso "rápido" de suporte).
resource "aws_vpc" "lab" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_security_group" "suporte" {
  name   = "loja-suporte"
  vpc_id = aws_vpc.lab.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
