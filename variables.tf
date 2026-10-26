# --- GITHUB ---

variable "github_token" {
  description = "GitHub token with repo admin permissions (for branch protection). Falls back to GITHUB_TOKEN env var when null — set automatically in GitHub Actions."
  type        = string
  sensitive   = true
  default     = null
}

# --- JAMF PRO CONNECTION ---

variable "jamfpro_instance_fqdn" {
  description = "Jamf Pro FQDN"
  type        = string
}

variable "jamfpro_client_id" {
  description = "Jamf Pro API Client ID"
  type        = string
  sensitive   = true
}

variable "jamfpro_client_secret" {
  description = "Jamf Pro API Client Secret"
  type        = string
  sensitive   = true
}

# --- JAMF APP CATALOG ---

variable "app_catalog_apps" {
  description = "Map of apps to deploy from Jamf App Catalog"
  type = map(object({
    app_title_name  = string
    enabled         = bool
    deployment_type = string
    smart_group_id  = number
  }))
  default = {}

  validation {
    condition = alltrue([
      for app in values(var.app_catalog_apps) :
      contains(["SELF_SERVICE", "INSTALL_AUTOMATICALLY"], app.deployment_type)
    ])
    error_message = "deployment_type must be either 'SELF_SERVICE' or 'INSTALL_AUTOMATICALLY'."
  }
}

# --- HOMEBREW ---

variable "homebrew_packages" {
  description = "Map of Homebrew packages to deploy via Self Service. Every package must set a non-empty icon_url so it always has a Self Service icon."
  type = map(object({
    formula        = string
    display_name   = string
    tap            = optional(string, "")
    cask           = optional(bool, false)
    icon_url       = optional(string, "")
    enabled        = bool
    smart_group_id = number
  }))
  default = {}

  validation {
    condition = alltrue([
      for pkg in values(var.homebrew_packages) : trimspace(pkg.icon_url) != ""
    ])
    error_message = "Every Homebrew package must set a non-empty icon_url so it always has a Self Service icon. Use an official-logo PNG (e.g. https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/<name>.png), or the generic https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/terminal.png fallback."
  }
}

# --- CROWDSTRIKE ---

variable "crowdstrike_cid" {
  description = "CrowdStrike Customer ID (CID) — 32 hex chars + '-XX' checksum, from Falcon Console → Sensor Downloads. Required for falconctl license."
  type        = string
  sensitive   = true
}

variable "crowdstrike_provisioning_token" {
  description = "CrowdStrike installation/provisioning token — from Falcon Console → Installation tokens. Passed as the optional second arg to falconctl license."
  type        = string
  sensitive   = true
  default     = "D56C4817"
}

# --- LENS ---

variable "lens_package_id" {
  description = "Jamf package ID for the Lens (Kubernetes IDE) installer. Look up under Settings → Packages in Jamf and paste the numeric ID into terraform.tfvars."
  type        = number
}

# --- SPLUNK MCP SERVER ---
# Lets Claude Code on a managed Mac query Splunk directly. Handled the same way
# as the CrowdStrike credentials above: sensitive tfvars value passed to the
# script as a policy parameter.
variable "splunk_mcp_endpoint" {
  description = "Splunk MCP Server endpoint, from the Splunk MCP Server app. Use the :443 /en-US/splunkd/__raw/services/mcp form — the :8089 management port is IP-allowlisted on Splunk Cloud and is not reachable from laptops off-network."
  type        = string
  default     = "https://example.splunkcloud.com:443/en-US/splunkd/__raw/services/mcp"
}

variable "splunk_mcp_token" {
  description = "Splunk MCP encrypted token (audience \"mcp\"), from the Splunk MCP Server app -> Create MCP Encrypted Token. Shown once. Rotating the app's encryption keys invalidates it."
  type        = string
  sensitive   = true
}
