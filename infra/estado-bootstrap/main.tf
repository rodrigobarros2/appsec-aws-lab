# Cria UMA vez o bucket do estado remoto do Terraform (o "ovo" antes da galinha).
# O state guarda ARNs, nomes e às vezes valores sensíveis: precisa de
# criptografia com chave própria, versionamento (desfazer um state corrompido),
# bloqueio público e acesso só por HTTPS. A trava fica no próprio S3
# (use_lockfile no backend), sem tabela DynamoDB.
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "regiao" {
  type    = string
  default = "sa-east-1"
}

provider "aws" {
  region = var.regiao
}

data "aws_caller_identity" "atual" {}
data "aws_partition" "atual" {}

resource "aws_kms_key" "estado" {
  description             = "Criptografia do estado do Terraform"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms_estado.json
}

data "aws_iam_policy_document" "kms_estado" {
  #checkov:skip=CKV_AWS_109:Key policy: Resource "*" se refere à própria chave.
  #checkov:skip=CKV_AWS_111:Key policy: Resource "*" se refere à própria chave.
  #checkov:skip=CKV_AWS_356:Key policy: Resource "*" se refere à própria chave.
  statement {
    sid       = "AdministracaoPelaConta"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.atual.partition}:iam::${data.aws_caller_identity.atual.account_id}:root"]
    }
  }
}

resource "aws_s3_bucket" "estado" {
  #checkov:skip=CKV_AWS_18:Acesso registrado por CloudTrail data events na conta.
  #checkov:skip=CKV_AWS_144:Estado de laboratório numa região; o versionamento cobre a recuperação.
  #checkov:skip=CKV2_AWS_62:O bucket de estado não dispara processamento.
  bucket_prefix = "appsec-aws-lab-tfstate-"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "estado" {
  bucket = aws_s3_bucket.estado.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "estado" {
  bucket                  = aws_s3_bucket.estado.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "estado" {
  bucket = aws_s3_bucket.estado.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "estado" {
  bucket = aws_s3_bucket.estado.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.estado.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "estado" {
  bucket = aws_s3_bucket.estado.id
  rule {
    id     = "versoes-antigas"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 180
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "estado" {
  bucket     = aws_s3_bucket.estado.id
  policy     = data.aws_iam_policy_document.estado.json
  depends_on = [aws_s3_bucket_public_access_block.estado]
}

data "aws_iam_policy_document" "estado" {
  statement {
    sid       = "SomenteHTTPS"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.estado.arn, "${aws_s3_bucket.estado.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

output "backend_hcl" {
  description = "Conteúdo do backend.hcl de infra/corrigido"
  value       = <<-EOT
    bucket     = "${aws_s3_bucket.estado.bucket}"
    region     = "${var.regiao}"
    kms_key_id = "${aws_kms_key.estado.arn}"
  EOT
}
