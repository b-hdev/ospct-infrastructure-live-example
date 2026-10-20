include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "tfr:///terraform-aws-modules/rds-aurora/aws?version=10.4.1"
}

dependency "vpc" {
  config_path = "../../networking/vpc/vpc-ospct"
  mock_outputs = {
    vpc_id           = "vpc-mock12345"
    database_subnets = ["subnet-mockdb01", "subnet-mockdb02", "subnet-mockdb03"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "init"]
}

dependency "rds_sg" {
  config_path = "../../networking/security-groups/rds-sg"
  mock_outputs = {
    id = "sg-mockrds01"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "init"]
}

inputs = {
  name           = "ospct-aurora-postgres"
  engine         = "aurora-postgresql"
  engine_version = "18.3"
  engine_mode    = "provisioned"

  # Arquitetura Serverless v2: escala capacidade (ACUs) automaticamente
  instances = {
    writer = {
      instance_class = "db.serverless"
    }
  }
  serverlessv2_scaling_configuration = {
    min_capacity = 0.5
    max_capacity = 2.0
  }
  # Parametros lidos do ambiente com senha no Secrets Manager
  database_name               = get_env("DB_NAME", "appdb")
  master_username             = get_env("DB_USERNAME", "dbadmin")
  manage_master_user_password = true

  # Rede: isolamento em subnets exclusivas de banco
  vpc_id                 = dependency.vpc.outputs.vpc_id
  subnets                = dependency.vpc.outputs.database_subnets
  create_db_subnet_group = true

  # Utiliza o Security Group controlado (liberado apenas para EC2 Bastion SSM)
  create_security_group  = false
  vpc_security_group_ids = [dependency.rds_sg.outputs.id]

  # =========================================================================
  # Protecoes de Dados:
  # Em PRODUCAO real:
  #   deletion_protection     = true
  #   skip_final_snapshot     = false
  #   backup_retention_period = 7 (ou 14/30 dias)
  # Em LABORATORIO (ajustado para teardown facil e Free Tier):
  # =========================================================================
  deletion_protection     = false
  skip_final_snapshot     = true
  backup_retention_period = 1

  storage_encrypted   = true
  apply_immediately   = true

  tags = {
    Terraform   = "true"
    Environment = "prod"
    ManagedBy   = "Terragrunt"
    Project     = "ospct"
  }
}