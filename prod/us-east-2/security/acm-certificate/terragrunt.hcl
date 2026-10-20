include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/modules/self-signed-cert"
}

inputs = {
  domain_name = "app.ospct.local"
  organization = "OSPCT Enterprise"

  tags = {
    Terraform = "true"
    Environment = "prod"
    ManagedBy = "Terragrunt"
    Project = "ospct"
    Purpose = "self-signed-certificate-for-alb"
  }
}