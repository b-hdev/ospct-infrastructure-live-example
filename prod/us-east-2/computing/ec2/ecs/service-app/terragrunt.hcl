include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "tfr:///terraform-aws-modules/ecs/aws//modules/service?version=7.6.1"
}

dependency "cluster" {
  config_path = "../cluster"
  mock_outputs = {
    arn = "arn:aws:ecs:us-east-2:123456789012:cluster/ospct-ecs-cluster"
  }
}

dependency "ec2_node" {
  config_path = "../ec2-node"
  mock_outputs = {
    id = "i-mockinstance01"
  }
}

inputs = {
  name = "nginx-app"

  cluster_arn = dependency.cluster.outputs.arn

  launch_type = "EC2"

  # Define que a Task Definition é compatível com EC2 (e não Fargate)
  requires_compatibilities = ["EC2"]


  #N- Copias
  desired_count = 1

  network_mode = "bridge"

  create_security_group = false

  cpu = 256
  memory = 128

  container_definitions = {
    nginx = {
      image = "nginxinc/nginx-unprivileged:1.31-alpine"
      # Porta 8080 interna do container mapeada para a porta 8080 da EC2 (host)
      portMappings = [
        {
          name          = "nginx"
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]
      memoryReservation      = 128
      readonlyRootFilesystem = false
      essential              = true
    }
  }
  tags = {
    Terraform   = "true"
    Environment = "prod"
    ManagedBy   = "Terragrunt"
  }
}
