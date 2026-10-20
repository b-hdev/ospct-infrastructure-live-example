# =============================================================================
# Módulo: GitHub OIDC Provider + IAM Role para GitHub Actions
# =============================================================================
#
# PROPÓSITO:
#   Configura autenticação federada entre GitHub Actions e AWS usando
#   OpenID Connect (OIDC). Elimina a necessidade de Access Keys estáticas.
#
# COMO FUNCIONA:
#   1. GitHub Actions gera um JWT token assinado pelo GitHub OIDC Provider
#   2. O JWT contém claims: repo, branch, workflow, etc.
#   3. AWS STS valida o JWT contra o OIDC Provider registrado
#   4. Se válido, AWS emite credenciais temporárias (15min-1h)
#   5. GitHub Actions usa essas credenciais para acessar ECR/ECS
#
# SEGURANÇA:
#   ✅ Sem secrets estáticos (credenciais são efêmeras)
#   ✅ Restrição por repositório (sub claim)
#   ✅ Restrição por branch (condition keys)
#   ✅ Princípio de menor privilégio (IAM policy mínima)
#   ✅ Auditável via CloudTrail
#
# REFERÊNCIA:
#   https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services
# =============================================================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# ── Variables ───────────────────────────────────────────────────────

variable "github_org" {
  description = "Nome da organização ou usuário no GitHub (ex: 'minha-org' ou 'meu-user')"
  type        = string
}

variable "github_repo" {
  description = "Nome do repositório GitHub (ex: 'infrastructure-live')"
  type        = string
}

variable "allowed_branches" {
  description = <<-EOT
    Lista de branches permitidas para assumir a IAM Role.
    Formato: ["main", "develop"]
    
    SEGURANÇA: Restrinja apenas às branches que precisam fazer deploy.
    Nunca use "*" em produção.
  EOT
  type        = list(string)
  default     = ["main"]
}

variable "ecr_repository_arn" {
  description = "ARN do repositório ECR que o GitHub Actions pode acessar"
  type        = string
}

variable "ecs_cluster_arn" {
  description = "ARN do cluster ECS que o GitHub Actions pode atualizar"
  type        = string
}

variable "ecs_service_name" {
  description = "Nome do ECS service que o GitHub Actions pode atualizar"
  type        = string
}

variable "iam_role_name" {
  description = "Nome da IAM Role que o GitHub Actions vai assumir"
  type        = string
  default     = "github-actions-deploy-role"
}

variable "tags" {
  description = "Tags para os recursos criados"
  type        = map(string)
  default     = {}
}

# ── Data Sources ────────────────────────────────────────────────────

# Obtém o ID da conta AWS atual
data "aws_caller_identity" "current" {}

# Obtém a região AWS atual
data "aws_region" "current" {}

# ── OIDC Provider ──────────────────────────────────────────────────
# Registra o GitHub como Identity Provider (IdP) confiável na AWS.
# Só é necessário UMA instância por conta AWS (não por repo).
#
# THUMBPRINT:
#   Certificado TLS do endpoint OIDC do GitHub.
#   AWS usa isso para validar que o token JWT veio realmente do GitHub.
#   O valor "6938fd4d98bab03faadb97b34396831e3780aea1" é o thumbprint
#   oficial do GitHub Actions, mas a AWS valida automaticamente desde 2023.
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  # Audiência: quem o token JWT foi emitido para
  # "sts.amazonaws.com" é o padrão do GitHub Actions para AWS
  client_id_list = ["sts.amazonaws.com"]

  # Thumbprint do certificado TLS do GitHub OIDC endpoint
  # Nota: Desde Jul/2023, a AWS valida automaticamente via raiz de confiança,
  # mas o campo ainda é obrigatório no Terraform
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = merge(var.tags, {
    Name = "github-actions-oidc-provider"
  })
}

# ── IAM Role ───────────────────────────────────────────────────────
# Role que o GitHub Actions assume via OIDC.
# A trust policy restringe QUEM pode assumir esta role.

resource "aws_iam_role" "github_actions" {
  name        = var.iam_role_name
  description = "IAM Role para GitHub Actions deploy via OIDC - Repo: ${var.github_org}/${var.github_repo}"

  # Trust Policy: Define QUEM pode assumir esta role
  # Condition restringe por repositório E branch
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowGitHubOIDC"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          # Valida que o token é para STS da AWS
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          # Restringe por repositório + branch (wildcard para ref types)
          # Formato do sub claim: "repo:<org>/<repo>:ref:refs/heads/<branch>"
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              for branch in var.allowed_branches :
              "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/${branch}"
            ]
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = var.iam_role_name
  })
}

# ── IAM Policy: ECR Access ─────────────────────────────────────────
# Permissões mínimas para o GitHub Actions interagir com ECR.
#
# Separadas em statements:
#   1. Login no ECR (GetAuthorizationToken) - recurso: "*" (obrigatório)
#   2. Pull/Push de imagens - recurso: ARN do repositório específico

resource "aws_iam_role_policy" "ecr_access" {
  name = "ecr-push-access"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRLogin"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        # GetAuthorizationToken não suporta resource-level permissions
        Resource = "*"
      },
      {
        Sid    = "ECRPushPull"
        Effect = "Allow"
        Action = [
          # Pull (necessário para cache de layers)
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          # Push
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = var.ecr_repository_arn
      }
    ]
  })
}

# ── IAM Policy: ECS Deploy ────────────────────────────────────────
# Permissões mínimas para atualizar o ECS service com nova task definition.
#
# POR QUE tantas actions?
#   O deploy no ECS envolve:
#   1. Ler a task definition atual (describe)
#   2. Registrar uma nova revisão (register)
#   3. Atualizar o service para usar a nova revisão (update)
#   4. Aguardar estabilidade (describe services/tasks)
#   5. PassRole para que o ECS possa assumir a execution role

resource "aws_iam_role_policy" "ecs_deploy" {
  name = "ecs-deploy-access"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECSTaskDefinition"
        Effect = "Allow"
        Action = [
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition"
        ]
        # Task definitions não suportam resource-level restrictions
        Resource = "*"
      },
      {
        Sid    = "ECSServiceUpdate"
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:DescribeTasks",
          "ecs:ListTasks"
        ]
        Resource = [
          var.ecs_cluster_arn,
          # Service ARN segue o padrão: arn:aws:ecs:region:account:service/cluster/service
          "arn:aws:ecs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:service/${element(split("/", var.ecs_cluster_arn), length(split("/", var.ecs_cluster_arn)) - 1)}/${var.ecs_service_name}",
          # Task ARN (wildcard pois tasks têm IDs dinâmicos)
          "arn:aws:ecs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:task/${element(split("/", var.ecs_cluster_arn), length(split("/", var.ecs_cluster_arn)) - 1)}/*"
        ]
      },
      {
        Sid    = "PassRoleToECS"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = [
          # Permite passar roles de execução do ECS
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*ecs*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*ECS*"
        ]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      }
    ]
  })
}

# ── Outputs ────────────────────────────────────────────────────────

output "oidc_provider_arn" {
  description = "ARN do OIDC Provider do GitHub (compartilhado por toda a conta AWS)"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "role_arn" {
  description = "ARN da IAM Role que o GitHub Actions assume (adicionar como GitHub Secret: AWS_ROLE_ARN)"
  value       = aws_iam_role.github_actions.arn
}

output "role_name" {
  description = "Nome da IAM Role"
  value       = aws_iam_role.github_actions.name
}
