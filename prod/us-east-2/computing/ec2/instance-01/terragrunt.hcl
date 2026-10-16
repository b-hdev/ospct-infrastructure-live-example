include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "tfr:///terraform-aws-modules/ec2-instance/aws?version=6.4.1"
}

dependency "vpc" {
  config_path = "../../../networking/vpc/vpc-ospct"
}

inputs = {
  name = "instance-01"

  instance_type = "t3.micro"
  key_name      = "user1"

  subnet_id              = dependency.vpc.outputs.private_subnets[0]
  create_eip = true

  security_group_rules = {
    ingress_ssh = {
      description = "Permitir SSH"
      cidr_blocks = ["0.0.0.0/0"]
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      type        = "ingress"
    }
    egress_all = {
      description = "Permitir todo o trafego de saida"
      cidr_blocks = ["0.0.0.0/0"]
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      type        = "egress"
    }
  }

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}
