include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "tfr:///terraform-aws-modules/secrets-manager/aws?version=2.2.0"
}

inputs = {
  name        = "ospct/prod/app-secrets"
  description = "Credenciais e tokens confidenciais da aplicacao"

  # Janela de recuperacao zerada para permitir recriacao imediata durante testes porém o certo seria 7d.
  recovery_window_in_days = 0

  secret_string = jsonencode({
    api_key     = get_env("APP_API_KEY")
    jwt_secret  = get_env("APP_JWT_SECRET")
    db_name     = get_env("DB_NAME", "appdb")
    db_username = get_env("DB_USERNAME", "dbadmin")
    environment = "production"
  })

  tags = {
    Terraform = "true"
    Environment = "prod"
    ManagedBy   = "Terragrunt"
    Project     = "ospct"
  }
}