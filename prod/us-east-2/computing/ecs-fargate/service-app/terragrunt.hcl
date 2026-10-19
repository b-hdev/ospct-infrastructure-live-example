include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "tfr:///terraform-aws-modules/ecs/aws//modules/service?version=7.6.1"
}

dependency "cluster" {
  config_path = "../cluster"
}

dependency "vpc" {
  config_path = "../../../networking/vpc/vpc-ospct"
}

inputs = {
  name = "nginx-fargate-app"
  cluster_arn = dependency.cluster.outputs.arn

  launch_type = "FARGATE"
  # Quantidade de réplicas do container
  desired_count = 1
  # Dimensões da Task Fargate (256 units = 0.25 vCPU, 512 MB de RAM)
  cpu    = 256
  memory = 512
  # REDE FARGATE: Coloca o container na subnet pública com IP público próprio
  subnet_ids       = dependency.vpc.outputs.public_subnets
  assign_public_ip = true

  create_security_group = true
  security_group_ingress_rules = {
    http = {
      description = "HTTP Container Nginx na porta 8080"
      cidr_ipv4   = "0.0.0.0/0"
      from_port   = 8080
      to_port     = 8080
      ip_protocol = "tcp"
    }
  }
  security_group_egress_rules = {
    all = {
      cidr_ipv4   = "0.0.0.0/0"
      ip_protocol = "-1"
    }
  }
  # DEFINIÇÃO DO CONTAINER DOCKER
  container_definitions = {
    nginx = {
      image = "nginxinc/nginx-unprivileged:1.31-alpine"
      # No modo Fargate (awsvpc), definimos apenas a porta interna do container
      portMappings = [
        {
          name          = "nginx"
          containerPort = 8080
          protocol      = "tcp"
        }
      ]
      readonlyRootFilesystem = false
      essential              = true
    }
  }
  tags = {
    Terraform   = "true"
    Environment = "prod"
    ManagedBy   = "Terragrunt"
    Project     = "ecs-fargate"
  }
}
