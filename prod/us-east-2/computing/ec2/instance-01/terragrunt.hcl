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

  subnet_id = dependency.vpc.outputs.public_subnets[0]
  
  create_eip = true

  create_security_group = true

  security_group_ingress_rules = {
    ssh = {
      description = "Permitir SSH"
      cidr_ipv4   = "0.0.0.0/0"
      from_port   = 22
      ip_protocol = "tcp"
      to_port     = 22
    }
  }

  security_group_egress_rules = {
    all = {
      cidr_ipv4   = "0.0.0.0/0"
      ip_protocol = "-1"
    }
  }

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}
