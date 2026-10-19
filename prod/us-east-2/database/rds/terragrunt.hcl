include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "tfr:///terraform-aws-modules/rds/aws?version=7.2.2"
}

dependency "vpc" {
  config_path = "../../networking/vpc/vpc-ospct"
}

dependency "rds_sg" {
  config_path = "../../networking/security-groups/rds-sg"
}

inputs = {
  identifier = "meu-rds-db"

  engine               = "postgres"
  engine_version       = "18.2"
  family               = "postgres18"
  major_engine_version = "18"
  instance_class       = "db.t4g.micro"

  allocated_storage     = 20
  max_allocated_storage = 100

  db_name  = "appdb"
  username = "dbadmin"
  port     = 5432

  manage_master_user_password = true

  create_db_subnet_group = true
  subnet_ids             = dependency.vpc.outputs.private_subnets

  # Referencia o SG criado como componente separado
  vpc_security_group_ids = [dependency.rds_sg.outputs.id]

  skip_final_snapshot = true
  deletion_protection = false

  tags = {
    Terraform   = "true"
    Environment = "dev"
    ManagedBy   = "Terragrunt"
    Project     = "ospct"
  }
}