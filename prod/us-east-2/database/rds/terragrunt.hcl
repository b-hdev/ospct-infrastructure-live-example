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
  # Nome padronizado do recurso
  identifier = "ospct-rds-postgres"

  engine               = "postgres"
  engine_version       = "18.2"
  family               = "postgres18"
  major_engine_version = "18"
  instance_class       = "db.t4g.micro"

  allocated_storage     = 20
  max_allocated_storage = 100

  # Parametros de conexao lidos da ENV (zero identificadores expostos no Git)
  db_name  = get_env("DB_NAME", "appdb")
  username = get_env("DB_USERNAME", "dbadmin")
  port     = 5432

  manage_master_user_password = true

  # Isolamento de rede: banco alocado exclusivamente nas database_subnets 
  create_db_subnet_group = true
  subnet_ids             = dependency.vpc.outputs.database_subnets

  # Referencia o SG criado como componente separado
  vpc_security_group_ids = [dependency.rds_sg.outputs.id]

  # Protecao ajustada para compatibilidade com conta Free Tier
    # =========================================================================
  # Protecoes de Dados:
  # Em PRODUCAO real:
  #   deletion_protection     = true
  #   skip_final_snapshot     = false
  #   backup_retention_period = 7 (ou 14/30 dias)
  # Em LABORATORIO (ajustado para teardown facil e Free Tier):
  # =========================================================================
  deletion_protection = false
  skip_final_snapshot = true
  backup_retention_period = 1

  tags = {
    Terraform   = "true"
    Environment = "prod"
    ManagedBy   = "Terragrunt"
    Project     = "ospct"
  }
}