# =============================================================================
# GitHub CI/CD IAM User - Credenciais para GitHub Actions → AWS
# =============================================================================
#
# PROPÓSITO:
#   Provisiona o IAM User com chaves de acesso para deploy automatizado
#   via GitHub Actions (ECR push + ECS Fargate deploy).
#
# APÓS APLICAR:
#   1. Obtenha a Access Key ID:
#      terragrunt output -raw access_key_id
#   2. Obtenha a Secret Access Key:
#      terragrunt output -raw secret_access_key
#   3. Adicione como GitHub Secrets no repositório:
#      - AWS_ACCESS_KEY_ID
#      - AWS_SECRET_ACCESS_KEY
# =============================================================================

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/modules/github-ci-user"
}

# ── Dependências ────────────────────────────────────────────────────
dependency "ecr" {
  config_path = "../../computing/ecr/app-repo"

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
inputs = {
  iam_user_name      = "ospct-github-actions-deployer"
  ecr_repository_arn = dependency.ecr.outputs.repository_arn
  ecs_cluster_arn    = dependency.ecs_cluster.outputs.arn
  ecs_service_name   = "nginx-fargate-app"

  tags = {
    Terraform   = "true"
    Environment = "prod"
    ManagedBy   = "Terragrunt"
    Project     = "ospct"
    Purpose     = "github-actions-ci-cd-deployer"
  }
}
