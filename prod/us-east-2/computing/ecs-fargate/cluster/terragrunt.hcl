include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "tfr:///terraform-aws-modules/ecs/aws//modules/cluster?version=7.6.1"
}

inputs = {
  name = "ospct-fargate-cluster"

  setting = [
    {
      name = "containerInsights"
      value = "enabled"
    }
  ]

#Provider FARGATE normal e SPOT *Desconto
  fargate_capacity_providers = {
    FARGATE = {
      default_capacity_provider_strategy = {
        weight = 50
        base = 1
      }
    }
    FARGATE_SPOT = {
      default_capacity_provider_strategy = {
        weight = 50 
      }
    }
  }

  tags = {
    Terraform = "true"
    Environment = "prod"
    Project     = "ecs-fargate"
    Name        = "ospct-fargate-cluster"
  }
}