# Retorna o ARN da identidade criada no SES (util para politicas IAM e permissoes)
output "arn" {
  description = "ARN da identidade de e-mail no SES"
  value       = aws_ses_email_identity.identity.arn
}

# Retorna o proprio e-mail configurado
output "email" {
  description = "O endereco de e-mail configurado"
  value       = aws_ses_email_identity.identity.email
}
