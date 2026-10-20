include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "tfr:///terraform-aws-modules/cloudwatch/aws//modules/metric-alarm?version=5.7.3"
}

dependency "ecs_cluster" {
  config_path = "../../computing/ecs-fargate/cluster"
  mock_outputs = {
    name = "ospct-fargate-cluster"
  }
}

dependency "ecs_service" {
  config_path = "../../computing/ecs-fargate/service-app"
  mock_outputs = {
    name = "nginx-fargate-app"
  }
}

inputs = {
  alarm_name        = "ospct-ecs-fargate-high-cpu"
  alarm_description = "Detecta alta utilização de CPU no cluster Fargate em 2 periodos consecutivos"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods    = 2
  threshold            = 80
  period               = 300
  unit                 = "Percent"

  namespace            = "AWS/ECS"
  metric_name          = "CPUUtilization"
  statistic            = "Average"

  dimensions = {
    ClusterName = dependency.ecs_cluster.outputs.name
    ServiceName = dependency.ecs_service.outputs.name
  }

  tags = {
    Terraform = "true"
    Environment = "prod"
    ManagedBy = "Terragrunt"
    Project = "ospct"
  }
}