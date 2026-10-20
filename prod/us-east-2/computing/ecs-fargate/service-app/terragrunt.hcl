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

dependency "secrets" {
  config_path = "../../../security/secrets-manager/app-secrets"
}

dependency "alb" {
  config_path = "../../../networking/alb-public"
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
  # REDE FARGATE: Container em subnet privada, sem IP publico, acessado exclusivamente via ALB
  subnet_ids       = dependency.vpc.outputs.private_subnets
  assign_public_ip = false

  load_balancer = {
    service = {
      target_group_arn = dependency.alb.outputs.target_groups["ecs-fargate"].arn
      container_name   = "nginx"
      container_port   = 8080
    }
  }

  # Secret ARNs para o container acessar
  task_exec_secret_arns = [
    dependency.secrets.outputs.secret_arn
  ]

  create_security_group = true
  security_group_ingress_rules = {
    alb_to_app = {
      description                  = "Acesso HTTP 8080 exclusivo a partir do ALB"
      from_port                    = 8080
      to_port                      = 8080
      ip_protocol                  = "tcp"
      referenced_security_group_id = dependency.alb.outputs.security_group_id
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
      secrets = [
        {
          name = "API_KEY"
          valueFrom = "${dependency.secrets.outputs.secret_arn}:api_key::"
        },
        {
          name = "JWT_SECRET"
          valueFrom = "${dependency.secrets.outputs.secret_arn}:jwt_secret::"
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
