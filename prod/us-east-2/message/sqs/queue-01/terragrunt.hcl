include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../../modules/sqs/queue"
}

inputs = {
  name = "queue-01"
  tags = {
    Terraform   = "true"
    Environment = "prod"
  }
}
