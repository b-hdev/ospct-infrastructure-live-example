include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "tfr:///terraform-aws-modules/vpc/aws?version=6.7.3"
}

inputs = {
  name = "ospct-vpc-prod"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-2a", "us-east-2b", "us-east-2c"]
  
  # Subnets de Aplicação (onde o Fargate e EC2 rodam protegidos)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]

  # Subnets Públicas (ALB, Gateway e Host Bastion)
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  # Subnets dedicadas e isoladas para Banco de Dados
  database_subnets                   = ["10.0.201.0/24", "10.0.202.0/24", "10.0.203.0/24"]
  create_database_subnet_group       = true
  create_database_subnet_route_table = true

  # Saída para internet das subnets privadas
  enable_nat_gateway     = true
  single_nat_gateway     = true
  enable_vpn_gateway     = false

  tags = {
    Terraform   = "true"
    Environment = "prod"
  }
}