include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "tfr:///terraform-aws-modules/ecs/aws//modules/service?version=7.6.1"
}

dependency "cluster" {
  config_path = "../cluster"
}

dependency "ec2_node" {
  config_path = "../ec2-node"
}

inputs = {
  name = "nginx-app"

  cluster_arn = dependency.cluster.outputs.arn

  launch_type = "EC2"

  #N- Copias
  desired_count = 1

  network_mode = "bridge"

  cpu = 512
  memory = 512

container_definitions = {
    nginx = {
      image = "public.ecr.aws/nginx/nginx:alpine"
      # Mapeamento de portas: Porta 80 do container exposta na porta 80 da EC2 (host)
      port_mappings = [
        {
          name          = "nginx"
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]
      # Recursos mínimos reservados para esse container dentro da task
      memory_reservation = 256
      essential          = true
    }
  }
  tags = {
    Terraform   = "true"
    Environment = "prod"
    ManagedBy   = "Terragrunt"
  }
}
