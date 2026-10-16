locals {
  # Automatically load account-level variables
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))

  # Automatically load region-level variables
  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  # Extract the variables we need for easy access
  account_name = local.account_vars.locals.account_name
  account_id   = local.account_vars.locals.aws_account_id
  aws_region   = local.region_vars.locals.aws_region
}

# Configure Terragrunt to automatically store tfstate files in an S3 bucket
remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = merge(
    {
      encrypt = true
      bucket  = "learning-tfstate-bhdev-${local.account_id}-${local.aws_region}"
      key     = "${path_relative_to_include()}/terraform.tfstate"
      region  = "${local.aws_region}"
    }
  )
}

# Generate an AWS provider block
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.aws_region}"

  # Only these AWS Account IDs may be operated on by this template
  allowed_account_ids = ["${local.account_id}"]
}
EOF
}

terraform {
  before_hook "before_hook" {
    commands = ["apply", "plan"]
    execute  = ["echo", "Running Terragrunt"]
  }

  after_hook "after_hook" {
    commands     = ["apply", "plan"]
    execute      = ["echo", "Finished running Terragrunt"]
    run_on_error = true
  }

  error_hook "import_resource" {
    commands = ["apply"]
    execute  = ["echo", "Error Hook executed"]
    on_errors = [
      ".*",
    ]
  }
}

errors {
  retry "keypair_not_found" {
    retryable_errors = [
      ".*creating EC2 Instance:.*InvalidKeyPair\\.NotFound: The key pair .* does not exist.*",
    ]
    max_attempts       = 3
    sleep_interval_sec = 5
  }
}


inputs = merge(
  local.account_vars.locals,
  local.region_vars.locals,
)
