include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "tfr:///terraform-aws-modules/alb/aws?version=10.5.1"
}

dependency "vpc" {
  config_path = "../vpc/vpc-ospct"
  mock_outputs = {
    vpc_id         = "vpc-00000000000000000"
    public_subnets = ["subnet-00000000000000001", "subnet-00000000000000002"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "init", "destroy"]
}

dependency "acm" {
  config_path = "../../security/acm-certificate"
  mock_outputs = {
    arn = "arn:aws:acm:us-east-2:123456789012:certificate/mock-cert-id"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "init", "destroy"]
}

inputs = {
  name = "ospct-alb-public"
  vpc_id = dependency.vpc.outputs.vpc_id

  subnets = dependency.vpc.outputs.public_subnets

  # Permite destroy sem bloqueio de protecao
  enable_deletion_protection = false

  create_security_group = true
  security_group_ingress_rules = {
    all_http = {
      from_port = 80
      to_port = 80
      ip_protocol = "tcp"
      description = "Entrada HTTP para redirect 301"
      cidr_ipv4   = "0.0.0.0/0"  
    }
    all_https = {
      from_port = 443
      to_port = 443
      ip_protocol = "tcp"
      description = "Trafego HTTPS publico criptografado"
      cidr_ipv4 = "0.0.0.0/0"
    }
  }
  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4 = "0.0.0.0/0"
    }
  }

  listeners = {
    # 1. Porta 80: Redireciona tudo que chegar em HTTP puro para HTTPS
    http_redirect = {
      port        = 80
      protocol    = "HTTP"
      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
    # 2. Porta 443: Entrada segura HTTPS conectada ao certificado ACM e ao Target Group Fargate
    https = {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = dependency.acm.outputs.arn
      forward = {
        target_group_key = "ecs-fargate"
      }
    }
  }
  target_groups = {
    ecs-fargate = {
      name_prefix = "app-"
      protocol = "HTTP"
      port = 8080
      # Obrigatorio "ip" para containers Fargate (modo awsvpc)
      target_type = "ip"
      deregistration_delay = 10
      create_attachment = false

      health_check = {
        enabled             = true
        interval = 30
        path = "/"
        port = "traffic-port"
        healthy_threshold = 3
        unhealthy_threshold = 3
        timeout = 6
        protocol = "HTTP"
        matcher = "200-399"
      }
    }
  }
  tags = {
    Terraform   = "true"
    Environment = "prod"
    Role        = "public-load-balancer"
  }
}