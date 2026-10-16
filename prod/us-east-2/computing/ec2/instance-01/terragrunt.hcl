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

  vpc_security_group_ids = [dependency.vpc.outputs.default_security_group_id]
  subnet_id              = dependency.vpc.outputs.private_subnets[0]

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}
