terraform {
  required_version = ">= 1.5.0"

  required_providers {
    jamfpro = {
      source  = "deploymenttheory/jamfpro"
      version = "~> 0.30.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}
