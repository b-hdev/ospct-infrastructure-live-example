include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/ses/email-identify"
}

inputs = {
  email = get_env("SES_EMAIL", "placeholder@exemplo.com")
}