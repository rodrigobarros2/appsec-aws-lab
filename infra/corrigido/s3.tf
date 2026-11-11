# Bucket de relatórios das lojas: privado, criptografado com KMS, versionado,
# só aceita HTTPS e expira versões antigas.
resource "aws_s3_bucket" "relatorios" {
  #checkov:skip=CKV_AWS_18:Acesso registrado por CloudTrail data events na conta (fora do escopo deste laboratório).
  #checkov:skip=CKV_AWS_144:Laboratório de uma região; replicação entra no plano de continuidade, não aqui.
  #checkov:skip=CKV2_AWS_62:O bucket não dispara processamento; notificações não se aplicam.
  bucket_prefix = "${local.prefixo}-relatorios-"
}

resource "aws_s3_bucket_ownership_controls" "relatorios" {
  bucket = aws_s3_bucket.relatorios.id
  rule {
    object_ownership = "BucketOwnerEnforced" # desliga ACLs
  }
}

resource "aws_s3_bucket_public_access_block" "relatorios" {
  bucket                  = aws_s3_bucket.relatorios.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "relatorios" {
  bucket = aws_s3_bucket.relatorios.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "relatorios" {
  bucket = aws_s3_bucket.relatorios.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.lab.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "relatorios" {
  bucket = aws_s3_bucket.relatorios.id
  rule {
    id     = "limpeza"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "relatorios" {
  bucket     = aws_s3_bucket.relatorios.id
  policy     = data.aws_iam_policy_document.relatorios.json
  depends_on = [aws_s3_bucket_public_access_block.relatorios]
}

data "aws_iam_policy_document" "relatorios" {
  statement {
    sid       = "SomenteHTTPS"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.relatorios.arn, "${aws_s3_bucket.relatorios.arn}/*"]
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
