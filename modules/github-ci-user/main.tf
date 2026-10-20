# =============================================================================
# GitHub CI/CD IAM User - Autenticação GitHub Actions → AWS
# =============================================================================
#
# PROPÓSITO:
#   Cria um usuário IAM dedicado para o GitHub Actions com permissões
#   estritamente limitadas ao ECR (push) e ECS Fargate (deploy).
#   Utilizado para ambientes onde Service Control Policies (SCPs) restringem
#   a criação de Identity Providers OIDC.
#
# RECURSOS CRIADOS:
#   1. aws_iam_user: Usuário dedicado com tags de rastreabilidade
#   2. aws_iam_access_key: Chave de acesso programática para o GitHub Actions
#   3. aws_iam_user_policy (ECR): Permissão de push apenas no repositório da app
#   4. aws_iam_user_policy (ECS): Permissão de deploy apenas no cluster/serviço da app
# =============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# ── Dados da Conta e Região ─────────────────────────────────────────

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── Variáveis ───────────────────────────────────────────────────────

variable "iam_user_name" {
  description = "Nome do usuário IAM para o GitHub Actions"
  type        = string
  default     = "ospct-github-actions-deployer"
}

variable "ecr_repository_arn" {
  description = "ARN do repositório ECR da aplicação (restrição de segurança)"
  type        = string
}

variable "ecs_cluster_arn" {
  description = "ARN do cluster ECS Fargate da aplicação"
  type        = string
}

variable "ecs_service_name" {
  description = "Nome do serviço ECS Fargate (usado para compor o ARN restrito)"
  type        = string
  default     = "nginx-fargate-app"
}

variable "tags" {
  description = "Tags para associar aos recursos IAM"
  type        = map(string)
  default     = {}
}

# ── 1. IAM User ─────────────────────────────────────────────────────

resource "aws_iam_user" "ci_user" {
  name          = var.iam_user_name
  force_destroy = true

  tags = merge(
    var.tags,
    {
      Name    = var.iam_user_name
      Purpose = "github-actions-ci-cd-deployer"
    }
  )
}

# ── 2. Access Key ───────────────────────────────────────────────────

resource "aws_iam_access_key" "ci_user_key" {
  user = aws_iam_user.ci_user.name
}

# ── 3. IAM Policy: Permissões ECR (Push/Pull) ───────────────────────

resource "aws_iam_user_policy" "ecr_access" {
  name = "ecr-push-access"
  user = aws_iam_user.ci_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRLogin"
        Effect   = "Allow"
        Action   = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid      = "ECRPushPull"
        Effect   = "Allow"
        Action   = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
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

# ── 4. IAM Policy: Permissões ECS (Deploy & Service Update) ──────────

resource "aws_iam_user_policy" "ecs_deploy" {
  name = "ecs-deploy-access"
  user = aws_iam_user.ci_user.name

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
          "arn:aws:ecs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:service/${element(split("/", var.ecs_cluster_arn), length(split("/", var.ecs_cluster_arn)) - 1)}/${var.ecs_service_name}",
          "arn:aws:ecs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:task/${element(split("/", var.ecs_cluster_arn), length(split("/", var.ecs_cluster_arn)) - 1)}/*"
        ]
      },
      {
        Sid    = "PassRoleToECS"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = [
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

# ── Outputs ─────────────────────────────────────────────────────────

output "iam_user_name" {
  description = "Nome do IAM User criado"
  value       = aws_iam_user.ci_user.name
}

output "iam_user_arn" {
  description = "ARN do IAM User criado"
  value       = aws_iam_user.ci_user.arn
}

output "access_key_id" {
  description = "Access Key ID para o GitHub Actions"
  value       = aws_iam_access_key.ci_user_key.id
}

output "secret_access_key" {
  description = "Secret Access Key para o GitHub Actions (sensível)"
  value       = aws_iam_access_key.ci_user_key.secret
  sensitive   = true
}
