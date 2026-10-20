include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "tfr:///terraform-aws-modules/ec2-instance/aws?version=6.4.1"
}

dependency "vpc" {
  config_path = "../../../../networking/vpc/vpc-ospct"
  mock_outputs = {
    private_subnets = ["subnet-mockprivate01"]
  }
}

dependency "cluster" {
  config_path = "../cluster/"
  mock_outputs = {
    name = "ospct-ecs-cluster"
  }
}

inputs = {
  name = "ecs-node-01"

  instance_type = "t3.micro"

  ami_ssm_parameter = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"

  create_iam_instance_profile = true
  iam_role_name = "ecs-instance-role-ospct"
  iam_role_policies = {
    AmazonEC2ContainerServiceforEC2Role = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
    # Permite administracao remota segura via AWS SSM Session Manager sem precisar de SSH
    AmazonSSMManagedInstanceCore        = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  # Rede Privada: no do ECS protegido dentro da VPC, sem IP publico direto 
  subnet_id                   = dependency.vpc.outputs.private_subnets[0]
  associate_public_ip_address = false

  create_security_group = true
  # Zero portas abertas para a internet (acesso via SSM e trafego controlado)
  security_group_ingress_rules = {}

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