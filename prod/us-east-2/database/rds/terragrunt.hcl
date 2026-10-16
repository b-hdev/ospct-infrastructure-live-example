include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "tfr:///terraform-aws-modules/rds/aws?version=7.2.2"
}

dependency "vpc" {
  config_path = "../../networking/vpc/vpc-ospct"
}

dependency "ec2" {
  config_path = "../../computing/ec2/instance-01"
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
  password = "SuaPasswordSegura123!"

  create_db_subnet_group = true
  subnet_ids             = dependency.vpc.outputs.private_subnets

  create_security_group = true
  vpc_id                = dependency.vpc.outputs.vpc_id

  security_group_rules = {
    ingress_ec2 = {
      description              = "Acesso PostgreSQL vindo da EC2"
      type                     = "ingress"
      from_port                = 5432
      to_port                  = 5432
      protocol                 = "tcp"
      source_security_group_id = dependency.ec2.outputs.security_group_id
    }
  }

  skip_final_snapshot  = true
  deletion_protection  = false

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}