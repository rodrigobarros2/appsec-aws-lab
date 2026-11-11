terraform {
  required_version = ">= 1.10"

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

  # Estado remoto: bucket criptografado com KMS, versionado e com trava nativa
  # (use_lockfile). O bucket é criado em ../estado-bootstrap. Bucket, região e
  # chave KMS ficam em backend.hcl, fora do Git:
  #   terraform init -backend-config=backend.hcl
  backend "s3" {
    key          = "appsec-aws-lab/corrigido.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.regiao

  default_tags {
    tags = {
      projeto  = "appsec-aws-lab"
      ambiente = var.ambiente
    }
  }
}

data "aws_caller_identity" "atual" {}
data "aws_partition" "atual" {}

locals {
  conta     = data.aws_caller_identity.atual.account_id
  particao  = data.aws_partition.atual.partition
  prefixo   = "loja-${var.ambiente}"
  raiz_arn  = "arn:${local.particao}:iam::${local.conta}:root"
}
