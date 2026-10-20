# =============================================================================
# GitHub OIDC Federation - Autenticação GitHub Actions → AWS
# =============================================================================
#
# PROPÓSITO:
#   Configura OpenID Connect (OIDC) para que o GitHub Actions possa
#   autenticar na AWS sem Access Keys estáticas.
#
# O QUE É CRIADO:
#   1. IAM OIDC Provider (registra GitHub como IdP confiável)
#   2. IAM Role com trust policy restrita ao repositório + branch main
#   3. IAM Policies com permissões mínimas para ECR push + ECS deploy
#
# APÓS APLICAR:
#   1. Copie o output 'role_arn'
#   2. Adicione como GitHub Secret: Settings → Secrets → Actions → AWS_ROLE_ARN
#   3. O pipeline .github/workflows/deploy.yml usará este ARN automaticamente
#
# SEGURANÇA:
#   ✅ Zero secrets estáticos
#   ✅ Credenciais temporárias (1h max)
#   ✅ Restrito à branch main do repositório específico
#   ✅ Least privilege: apenas ECR push + ECS deploy
# =============================================================================

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/modules/github-oidc"
}

# ── Dependências ────────────────────────────────────────────────────
# Precisa dos ARNs do ECR e ECS que já foram provisionados

dependency "ecr" {
  config_path = "../../computing/ecr/app-repo"

  # Mock para validate/init (sem acesso real ao state)
  mock_outputs_allowed_terraform_commands = ["validate", "init"]
  mock_outputs = {
    repository_arn = "arn:aws:ecr:us-east-2:000000000000:repository/mock-repo"
  }
}

dependency "ecs_cluster" {
  config_path = "../../computing/ecs-fargate/cluster"

  mock_outputs_allowed_terraform_commands = ["validate", "init"]
  mock_outputs = {
    arn = "arn:aws:ecs:us-east-2:000000000000:cluster/mock-cluster"
  }
}

# ── Inputs ──────────────────────────────────────────────────────────
# SEGURANÇA: Todos os dados identificáveis são lidos de variáveis de ambiente.
# Mesmo que o arquivo seja commitado, nenhuma informação sensível vaza.
#
# Variáveis necessárias (exportar antes de rodar terragrunt):
#   export GITHUB_ORG="seu-usuario-ou-org"
#   export GITHUB_REPO="nome-do-repo"

inputs = {
  # Dados do repositório GitHub (fail-fast: erro se não definidos)
  github_org  = get_env("GITHUB_ORG")
  github_repo = get_env("GITHUB_REPO")

  # Branches autorizadas a fazer deploy (restrição de segurança)
  allowed_branches = ["main"]

  # ARNs dos recursos que o GitHub Actions pode acessar
  ecr_repository_arn = dependency.ecr.outputs.repository_arn
  ecs_cluster_arn    = dependency.ecs_cluster.outputs.arn
  ecs_service_name   = "nginx-fargate-app"

  # Nome da IAM Role
  iam_role_name = "ospct-github-actions-deploy"

  tags = {
    Terraform   = "true"
    Environment = "prod"
    ManagedBy   = "Terragrunt"
    Project     = "ospct"
    Purpose     = "github-actions-oidc-federation"
  }
}
