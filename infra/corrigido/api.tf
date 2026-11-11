# API Gateway (REST): autorizador JWT em todas as rotas de loja, WAF com regras
# gerenciadas e limite por IP, logs de acesso criptografados e throttling.
resource "aws_api_gateway_rest_api" "loja" {
  name = "${local.prefixo}-api"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  lifecycle {
    create_before_destroy = true
  }
}

# Validação na borda: o API Gateway rejeita corpo fora do schema antes de
# chamar a Lambda. additionalProperties = false barra campos como "total" e
# "valorDesconto", que o cliente não tem o direito de mandar.
resource "aws_api_gateway_request_validator" "completo" {
  name                        = "corpo-e-parametros"
  rest_api_id                 = aws_api_gateway_rest_api.loja.id
  validate_request_body       = true
  validate_request_parameters = true
}

resource "aws_api_gateway_model" "pedido" {
  rest_api_id  = aws_api_gateway_rest_api.loja.id
  name         = "Pedido"
  content_type = "application/json"
  schema = jsonencode({
    "$schema"            = "http://json-schema.org/draft-04/schema#"
    type                 = "object"
    required             = ["itens", "telefone"]
    additionalProperties = false
    properties = {
      telefone = { type = "string", pattern = "^[0-9]{10,13}$" }
      itens = {
        type     = "array"
        minItems = 1
        maxItems = 50
        items = {
          type                 = "object"
          required             = ["produtoId", "quantidade"]
          additionalProperties = false
          properties = {
            produtoId  = { type = "string", maxLength = 64 }
            quantidade = { type = "integer", minimum = 1, maximum = 99 }
          }
        }
      }
    }
  })
}

resource "aws_api_gateway_model" "resgate" {
  rest_api_id  = aws_api_gateway_rest_api.loja.id
  name         = "Resgate"
  content_type = "application/json"
  schema = jsonencode({
    "$schema"            = "http://json-schema.org/draft-04/schema#"
    type                 = "object"
    required             = ["codigo", "pedidoId"]
    additionalProperties = false
    properties = {
      codigo   = { type = "string", pattern = "^[A-Z0-9-]{3,32}$" }
      pedidoId = { type = "string", maxLength = 64 }
    }
  })
}

resource "aws_api_gateway_authorizer" "jwt" {
  name                             = "jwt"
  rest_api_id                      = aws_api_gateway_rest_api.loja.id
  type                             = "TOKEN"
  identity_source                  = "method.request.header.Authorization"
  identity_validation_expression   = "^Bearer [\\w-]+\\.[\\w-]+\\.[\\w-]+$"
  authorizer_uri                   = aws_lambda_function.funcao["autorizador"].invoke_arn
  authorizer_result_ttl_in_seconds = 300
}

# Árvore de recursos: /lojas/{lojaId}/cupons/{codigo}, /pedidos, /cupons/resgatar, /webhooks/pagamento
resource "aws_api_gateway_resource" "lojas" {
  rest_api_id = aws_api_gateway_rest_api.loja.id
  parent_id   = aws_api_gateway_rest_api.loja.root_resource_id
  path_part   = "lojas"
}

resource "aws_api_gateway_resource" "loja_id" {
  rest_api_id = aws_api_gateway_rest_api.loja.id
  parent_id   = aws_api_gateway_resource.lojas.id
  path_part   = "{lojaId}"
}

resource "aws_api_gateway_resource" "loja_cupons" {
  rest_api_id = aws_api_gateway_rest_api.loja.id
  parent_id   = aws_api_gateway_resource.loja_id.id
  path_part   = "cupons"
}

resource "aws_api_gateway_resource" "codigo" {
  rest_api_id = aws_api_gateway_rest_api.loja.id
  parent_id   = aws_api_gateway_resource.loja_cupons.id
  path_part   = "{codigo}"
}

resource "aws_api_gateway_resource" "pedidos" {
  rest_api_id = aws_api_gateway_rest_api.loja.id
  parent_id   = aws_api_gateway_rest_api.loja.root_resource_id
  path_part   = "pedidos"
}

resource "aws_api_gateway_resource" "cupons" {
  rest_api_id = aws_api_gateway_rest_api.loja.id
  parent_id   = aws_api_gateway_rest_api.loja.root_resource_id
  path_part   = "cupons"
}

resource "aws_api_gateway_resource" "resgatar" {
  rest_api_id = aws_api_gateway_rest_api.loja.id
  parent_id   = aws_api_gateway_resource.cupons.id
  path_part   = "resgatar"
}

resource "aws_api_gateway_resource" "webhooks" {
  rest_api_id = aws_api_gateway_rest_api.loja.id
  parent_id   = aws_api_gateway_rest_api.loja.root_resource_id
  path_part   = "webhooks"
}

resource "aws_api_gateway_resource" "pagamento" {
  rest_api_id = aws_api_gateway_rest_api.loja.id
  parent_id   = aws_api_gateway_resource.webhooks.id
  path_part   = "pagamento"
}

locals {
  rotas_autenticadas = {
    cupom    = { recurso = aws_api_gateway_resource.codigo.id, metodo = "GET", modelo = null }
    pedidos  = { recurso = aws_api_gateway_resource.pedidos.id, metodo = "POST", modelo = aws_api_gateway_model.pedido.name }
    resgatar = { recurso = aws_api_gateway_resource.resgatar.id, metodo = "POST", modelo = aws_api_gateway_model.resgate.name }
  }
}

resource "aws_api_gateway_method" "autenticada" {
  for_each      = local.rotas_autenticadas
  rest_api_id   = aws_api_gateway_rest_api.loja.id
  resource_id   = each.value.recurso
  http_method   = each.value.metodo
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.jwt.id

  request_validator_id = aws_api_gateway_request_validator.completo.id
  request_models       = each.value.modelo == null ? {} : { "application/json" = each.value.modelo }
  request_parameters = each.key == "cupom" ? {
    "method.request.path.lojaId" = true
    "method.request.path.codigo" = true
  } : {}
}

resource "aws_api_gateway_integration" "autenticada" {
  for_each                = local.rotas_autenticadas
  rest_api_id             = aws_api_gateway_rest_api.loja.id
  resource_id             = each.value.recurso
  http_method             = aws_api_gateway_method.autenticada[each.key].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.funcao[each.key].invoke_arn
}

# O provedor de pagamento não manda JWT: a rota é aberta no API Gateway e a
# autenticação é a assinatura HMAC conferida na Lambda (tempo constante).
resource "aws_api_gateway_method" "webhook" {
  #checkov:skip=CKV_AWS_59:Webhook do provedor de pagamento; autenticado por HMAC na função (ver app/corrigido/src/loja.mjs) e protegido pelo WAF.
  rest_api_id   = aws_api_gateway_rest_api.loja.id
  resource_id   = aws_api_gateway_resource.pagamento.id
  http_method   = "POST"
  authorization = "NONE"

  request_validator_id = aws_api_gateway_request_validator.completo.id
  request_parameters = {
    "method.request.header.x-assinatura" = true
  }
}

resource "aws_api_gateway_integration" "webhook" {
  rest_api_id             = aws_api_gateway_rest_api.loja.id
  resource_id             = aws_api_gateway_resource.pagamento.id
  http_method             = aws_api_gateway_method.webhook.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.funcao["webhook"].invoke_arn
}

resource "aws_lambda_permission" "api" {
  for_each      = toset(["autorizador", "cupom", "pedidos", "resgatar", "webhook"])
  statement_id  = "InvocadaPeloApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.funcao[each.key].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.loja.execution_arn}/*"
}

resource "aws_api_gateway_deployment" "loja" {
  rest_api_id = aws_api_gateway_rest_api.loja.id

  triggers = {
    redeploy = sha1(jsonencode([
      aws_api_gateway_method.autenticada,
      aws_api_gateway_integration.autenticada,
      aws_api_gateway_method.webhook,
      aws_api_gateway_integration.webhook,
      aws_api_gateway_authorizer.jwt,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/apigateway/${local.prefixo}-api"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.lab.arn
}

resource "aws_api_gateway_stage" "v1" {
  #checkov:skip=CKV_AWS_120:Cache desligado de propósito: as respostas dependem da loja autenticada e cache de rota autenticada vaza dado entre lojas.
  #checkov:skip=CKV2_AWS_51:Backend é Lambda (AWS_PROXY), não HTTP; certificado de cliente não se aplica.
  rest_api_id          = aws_api_gateway_rest_api.loja.id
  deployment_id        = aws_api_gateway_deployment.loja.id
  stage_name           = "v1"
  xray_tracing_enabled = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format = jsonencode({
      requestId = "$context.requestId"
      ip        = "$context.identity.sourceIp"
      metodo    = "$context.httpMethod"
      rota      = "$context.resourcePath"
      status    = "$context.status"
      loja      = "$context.authorizer.lojaId"
      waf       = "$context.waf.status"
      latencia  = "$context.responseLatency"
    })
  }

  depends_on = [aws_api_gateway_account.conta]
}

resource "aws_api_gateway_method_settings" "todas" {
  #checkov:skip=CKV_AWS_225:Cache desligado de propósito (ver o estágio v1).
  rest_api_id = aws_api_gateway_rest_api.loja.id
  stage_name  = aws_api_gateway_stage.v1.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled        = true
    logging_level          = "INFO"
    data_trace_enabled     = false # não registrar corpo de requisição (dados pessoais)
    throttling_burst_limit = 50
    throttling_rate_limit  = 100
  }
}

# Papel que permite ao API Gateway escrever logs no CloudWatch (configuração da conta).
data "aws_iam_policy_document" "assumir_apigateway" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "apigateway_logs" {
  name               = "${local.prefixo}-apigateway-logs"
  assume_role_policy = data.aws_iam_policy_document.assumir_apigateway.json
}

resource "aws_iam_role_policy_attachment" "apigateway_logs" {
  role       = aws_iam_role.apigateway_logs.name
  policy_arn = "arn:${local.particao}:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "conta" {
  cloudwatch_role_arn = aws_iam_role.apigateway_logs.arn
}

# WAF: regras gerenciadas (OWASP comum, entradas maliciosas conhecidas) e limite por IP.
resource "aws_wafv2_web_acl" "api" {
  name  = "${local.prefixo}-api"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "limite-por-ip"
    priority = 0
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = var.limite_requisicoes_por_ip
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "limite-por-ip"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "regras-comuns"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "regras-comuns"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "entradas-maliciosas"
    priority = 2
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "entradas-maliciosas"
      sampled_requests_enabled   = true
    }
  }

  # IPs anônimos (Tor, VPNs de anonimização): bloqueia. IPs de provedores de
  # nuvem: só conta, porque o webhook do provedor de pagamento vem de nuvem.
  rule {
    name     = "ips-anonimos"
    priority = 3
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesAnonymousIpList"
        rule_action_override {
          name = "HostingProviderIPList"
          action_to_use {
            count {}
          }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "ips-anonimos"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.prefixo}-api"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "api" {
  resource_arn = aws_api_gateway_stage.v1.arn
  web_acl_arn  = aws_wafv2_web_acl.api.arn
}

resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-${local.prefixo}-api" # o WAF exige o prefixo aws-waf-logs-
  retention_in_days = 365
  kms_key_id        = aws_kms_key.lab.arn
}

resource "aws_wafv2_web_acl_logging_configuration" "api" {
  resource_arn            = aws_wafv2_web_acl.api.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }
}
