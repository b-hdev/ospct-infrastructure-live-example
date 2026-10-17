include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "tfr:///terraform-aws-modules/ec2-instance/aws?version=6.4.1"
}

dependency "vpc" {
  config_path = "../../../../networking/vpc/vpc-ospct"
}

dependency "cluster" {
  config_path = "../cluster/"
}

inputs = {
  name = "ecs-node-01"

  instance_type = "t3.micro"

  key_name = "user1"

  ami = "ami-0b44aeebc597022d4"

  create_iam_instance_profile = true
  iam_role_name = "ecs-instance-role-ospct"
  iam_role_policies = {
    AmazonEC2ContainerServiceforEC2Role = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
  }

  subnet_id = dependency.vpc.outputs.public_subnets[0]
  associate_public_ip_address = true

  create_security_group = true
  security_group_ingress_rules = {
    ssh = {
      description = "SSH"
      cidr_ipv4 = "0.0.0.0/0"
      from_port = 22
      to_port = 22
      ip_protocol = "tcp"
    }

    http = {
      description = "HTTP Container"
      cidr_ipv4 = "0.0.0.0/0"
      from_port = 80
      to_port = 80
      ip_protocol = "tcp"
    }
  }

  security_group_egress_rules = {
    all = {
      cidr_ipv4 = "0.0.0.0/0"
      ip_protocol = "-1"
    }
  }
  #Script pre load
  user_data = <<-EOT
    #!/bin/bash
    echo "ECS_CLUSTER=${dependency.cluster.outputs.name}" >> /etc/ecs/ecs.config
  EOT
  tags = {
    Terraform   = "true"
    Environment = "prod"
  }
}