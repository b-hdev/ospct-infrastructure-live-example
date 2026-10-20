include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "tfr:///terraform-aws-modules/alb/aws?version=10.5.1"
}

dependency "vpc" {
  config_path = "../vpc/vpc-ospct"
}

inputs = {
  name = "ospct-alb-public"
  vpc_id = dependency.vpc.outputs.vpc_id

  subnets = dependency.vpc.outputs.public_subnets

  create_security_group = true
  security_group_ingress_rules = {
    all_http = {
      from_port = 80
      to_port = 80
      ip_protocol = "tcp"
      description = "Trafego HTTP publico da internet"
      cidr_ipv4   = "0.0.0.0/0"  
    }
  }
  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4 = "0.0.0.0/0"
    }
  }

  listeners = {
    http = {
      port       = 80
      protocol   = "HTTP"
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