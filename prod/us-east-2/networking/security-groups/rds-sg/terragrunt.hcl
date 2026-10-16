include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "tfr:///terraform-aws-modules/security-group/aws?version=6.0.0"
}

dependency "vpc" {
  config_path = "../../vpc/vpc-ospct"
}

dependency "ec2" {
  config_path = "../../../computing/ec2/instance-01"
}

inputs = {
  name        = "meu-rds-db-sg"
  description = "Security group for PostgreSQL RDS accessed by EC2"
  vpc_id      = dependency.vpc.outputs.vpc_id

  ingress_rules = {
    postgresql_from_ec2 = {
      description                = "PostgreSQL from EC2"
      from_port                  = 5432
      to_port                    = 5432
      ip_protocol                = "tcp"
      referenced_security_group_id = dependency.ec2.outputs.security_group_id
    }
  }

  egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}
