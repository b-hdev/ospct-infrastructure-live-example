include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "tfr:///terraform-aws-modules/ecs/aws//modules/cluster?version=7.6.1"
}

inputs = {
  name = "ospct-ecs-cluster"

  setting = [
    {
      name  = "containerInsights"
      value = "enabled"
    }
  ]

  tags = {
    Terraform   = "true"
    Environment = "prod"
    ManagedBy   = "Terragrunt"
    Project     = "ospct"
  }
}