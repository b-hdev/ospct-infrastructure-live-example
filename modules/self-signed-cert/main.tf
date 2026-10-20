terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}

variable "domain_name" {
  description = "Nome de dominio comum (Common Name) para o certificado SSL/TLS"
  type        = string
  default     = "app.ospct.local"
}

variable "organization" {
  description = "Nome da organizacao para o certificado"
  type        = string
  default     = "OSPCT Enterprise"
}

variable "tags" {
  description = "Tags para associar ao recurso no ACM"
  type        = map(string)
  default     = {}
}

# 1. Gera uma chave privada RSA de 2048 bits
resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# 2. Gera o certificado X.509 autoassinado
resource "tls_self_signed_cert" "this" {
  private_key_pem = tls_private_key.this.private_key_pem

  subject {
    common_name  = var.domain_name
    organization = var.organization
  }

  validity_period_hours = 8760 # Valido por 1 ano

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# 3. Importa o certificado autoassinado para o AWS Certificate Manager (ACM)
resource "aws_acm_certificate" "this" {
  private_key      = tls_private_key.this.private_key_pem
  certificate_body = tls_self_signed_cert.this.cert_pem

  tags = var.tags
}

output "arn" {
  description = "ARN do certificado SSL/TLS registrado no AWS ACM"
  value       = aws_acm_certificate.this.arn
}

output "domain_name" {
  description = "Nome de dominio associado ao certificado"
  value       = var.domain_name
}
