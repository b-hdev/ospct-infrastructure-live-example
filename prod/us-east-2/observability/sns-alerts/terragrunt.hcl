include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "tfr:///terraform-aws-modules/sns/aws?version=7.2.0"
}

inputs = {
  name = "ospct-cloudwatch-alerts-topic"

  subscriptions = {
    email_devops = {
      protocol = "email"
      endpoint = get_env("SES_EMAIL")
    }
  }

  tags = {
    Terraform   = "true"
    Environment = "prod"
    ManagedBy   = "Terragrunt"
    Project     = "ospct"
  }
}