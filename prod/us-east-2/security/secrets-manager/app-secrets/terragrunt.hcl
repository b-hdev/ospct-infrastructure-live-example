include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "tfr:///terraform-aws-modules/secrets-manager/aws?version=2.2.0"
}

inputs = {
  name        = "ospct/prod/app-credentials"
  description = "Credenciais e tokens confidenciais da aplicacao"

  recovery_window_in_days = 0

  secret_string = jsonencode({
    api_key    = "123"
    jwt_secret = "123_@!#"
    environment = "production"
  })

  tags = {
    Terraform = "true"
    Environment = "prod"
    ManagedBy   = "Terragrunt"
    Project     = "ospct"
  }
}