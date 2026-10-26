provider "github" {
  owner = "your-github-org"
  token = var.github_token # null → falls back to GITHUB_TOKEN env var (auto-set in Actions)
}

provider "jamfpro" {
  jamfpro_instance_fqdn                = var.jamfpro_instance_fqdn
  auth_method                          = "oauth2"
  client_id                            = var.jamfpro_client_id
  client_secret                        = var.jamfpro_client_secret
  jamfpro_load_balancer_lock           = true
  mandatory_request_delay_milliseconds = 100
  token_refresh_buffer_period_seconds  = 40
}
