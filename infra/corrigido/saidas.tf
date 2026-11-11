output "url_api" {
  description = "URL base da API"
  value       = aws_api_gateway_stage.v1.invoke_url
}

output "bucket_relatorios" {
  value = aws_s3_bucket.relatorios.bucket
}

output "segredos_para_preencher" {
  description = "Grave os valores fora do Terraform (ver docs/segredos.md)"
  value       = [aws_secretsmanager_secret.jwt.name, aws_secretsmanager_secret.webhook.name]
}
