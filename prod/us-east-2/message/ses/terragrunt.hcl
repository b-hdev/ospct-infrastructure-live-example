include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/ses/email-identify"
}

inputs = {
  email = "[EMAIL_ADDRESS]"
}