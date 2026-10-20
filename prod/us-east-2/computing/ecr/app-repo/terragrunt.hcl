include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "tfr:///terraform-aws-modules/ecr/aws?version=3.2.0"
}

inputs = {
  repository_name                   = "ospct-app-repo"
  repository_image_tag_mutability   = "MUTABLE"
  repository_image_scan_on_push     = true
  repository_force_delete           = true

  # Politica de ciclo de vida: retém apenas as últimas 10 imagens para não gerar custo de storage
  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Manter apenas as ultimas 5 imagens"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })

  tags = {
    Terraform   = "true"
    Environment = "prod"
    ManagedBy   = "Terragrunt"
    Project     = "ospct"
  }
}
