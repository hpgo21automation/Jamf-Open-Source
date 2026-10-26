# --- CROWDSTRIKE SENSOR STATUS ---

resource "jamfpro_computer_extension_attribute" "crowdstrike_status" {
  name                   = "CrowdStrike Sensor Status"
  description            = "Reports the status of the CrowdStrike Falcon sensor"
  data_type              = "STRING"
  enabled                = true
  input_type             = "SCRIPT"
  inventory_display_type = "EXTENSION_ATTRIBUTES"
  script_contents = templatefile("${path.module}/scripts/ea_crowdstrike_status.sh", {
    expected_cid = var.crowdstrike_cid
  })
}

# --- ENTRA DEPARTMENT MAPPING ---
resource "jamfpro_computer_extension_attribute" "entra_department" {
  name                   = "Entra Department"
  description            = "Department synced from Entra ID via directory service attribute mapping"
  data_type              = "STRING"
  enabled                = true
  input_type             = "DIRECTORY_SERVICE_ATTRIBUTE_MAPPING"
  inventory_display_type = "USER_AND_LOCATION"
  ldap_attribute_mapping = "department"
}

# --- HOMEBREW DAEMON STATUS EXTENSION ATTRIBUTE ---
resource "jamfpro_computer_extension_attribute" "homebrew_daemon_status" {
  name                   = "Homebrew Monitor Daemon Status"
  description            = "Reports whether the Homebrew blocking daemon is installed and running"
  data_type              = "STRING"
  enabled                = true
  input_type             = "SCRIPT"
  inventory_display_type = "EXTENSION_ATTRIBUTES"
  script_contents        = file("${path.module}/scripts/ea_homebrew_daemon_status.sh")
}

# --- HOMEBREW INSTALL FAILURES ---
resource "jamfpro_computer_extension_attribute" "homebrew_install_failures" {
  name                   = "Homebrew Install Failures"
  description            = "Comma-separated list of Homebrew packages whose most recent install run failed (or None). Read from per-formula status files written by homebrew_package_installer.sh."
  data_type              = "STRING"
  enabled                = true
  input_type             = "SCRIPT"
  inventory_display_type = "EXTENSION_ATTRIBUTES"
  script_contents        = file("${path.module}/scripts/ea_homebrew_install_failures.sh")
}

# --- HOMEBREW WEEKLY UPGRADE STATUS ---
resource "jamfpro_computer_extension_attribute" "homebrew_upgrade_status" {
  name                   = "Homebrew Upgrade Status"
  description            = "Outcome of the last weekly Homebrew upgrade run (OK / FAIL: reason / No Data), written by upgrade_homebrew_packages.sh."
  data_type              = "STRING"
  enabled                = true
  input_type             = "SCRIPT"
  inventory_display_type = "EXTENSION_ATTRIBUTES"
  script_contents        = file("${path.module}/scripts/ea_homebrew_upgrade_status.sh")
}

# --- HOMEBREW DETECTION EXTENSION ATTRIBUTE ---
resource "jamfpro_computer_extension_attribute" "homebrew_status" {
  name                   = "User Homebrew Installations"
  description            = "Reports any Homebrew installations found in user directories (excluding srv_* accounts)"
  data_type              = "STRING"
  enabled                = true
  input_type             = "SCRIPT"
  inventory_display_type = "EXTENSION_ATTRIBUTES"
  script_contents        = file("${path.module}/scripts/ea_homebrew_status.sh")
}

# --- JAMF CONNECT VERSION ---
resource "jamfpro_computer_extension_attribute" "jamf_connect_version" {
  name                   = "Jamf Connect - Connect Login Plugin Version"
  description            = "Displays the version of the currently installed Jamf Connect login window security agent plugin"
  data_type              = "STRING"
  enabled                = true
  input_type             = "SCRIPT"
  inventory_display_type = "EXTENSION_ATTRIBUTES"
  script_contents        = file("${path.module}/scripts/ea_jamf_connect_version.sh")
}

# --- SECURE TOKEN EXTENSION ATTRIBUTE ---
resource "jamfpro_computer_extension_attribute" "secure_token_status" {
  name                   = "Secure Token Status"
  description            = "Reports whether any local user has a Secure Token"
  data_type              = "STRING"
  enabled                = true
  input_type             = "SCRIPT"
  inventory_display_type = "EXTENSION_ATTRIBUTES"
  script_contents        = file("${path.module}/scripts/ea_secure_token.sh")
}

# --- SPLUNK INPUTS VERSION TRACKING ---
resource "jamfpro_computer_extension_attribute" "splunk_inputs_version" {
  name                   = "Splunk Inputs Script Version"
  description            = "Tracks which version of the Splunk inputs config script has run"
  data_type              = "STRING"
  enabled                = true
  input_type             = "SCRIPT"
  inventory_display_type = "EXTENSION_ATTRIBUTES"
  script_contents        = file("${path.module}/scripts/ea_splunk_inputs_version.sh")
}

# --- SPLUNK UF LAST-RUN STATUS ---
resource "jamfpro_computer_extension_attribute" "splunk_uf_status" {
  name                   = "Splunk UF Status"
  description            = "Outcome of the last Splunk UF install/upgrade run (OK / FAIL: reason / No Data), written by install_splunk_uf.sh. Drives the Needs Remediation smart group."
  data_type              = "STRING"
  enabled                = true
  input_type             = "SCRIPT"
  inventory_display_type = "EXTENSION_ATTRIBUTES"
  script_contents        = file("${path.module}/scripts/ea_splunk_uf_status.sh")
}

# --- SPLUNK UF VERSION TRACKING ---
resource "jamfpro_computer_extension_attribute" "splunk_uf_version" {
  name                   = "Splunk UF Version"
  description            = "Reports the installed Splunk Universal Forwarder version; drives the Needs Upgrade smart group"
  data_type              = "STRING"
  enabled                = true
  input_type             = "SCRIPT"
  inventory_display_type = "EXTENSION_ATTRIBUTES"
  script_contents        = file("${path.module}/scripts/ea_splunk_uf_version.sh")
}

# --- SPLUNK MCP AUTH STATUS ---
# Probes whether the deployed Splunk MCP token actually authenticates, rather
# than only whether the config file was written (which the splunk-mcp.status
# file reports and which stays OK even with a rejected token). Drives the
# "Splunk MCP - Auth Failing" smart group.
resource "jamfpro_computer_extension_attribute" "splunk_mcp_status" {
  name                   = "Splunk MCP Status"
  description            = "Result of the Splunk MCP initialize handshake using the deployed token (OK / AUTH_FAIL / UNREACHABLE / NO_CONFIG). Catches a bad or expired token, which the splunk-mcp.status file does not. Drives the 'Splunk MCP - Auth Failing' smart group."
  data_type              = "STRING"
  enabled                = true
  input_type             = "SCRIPT"
  inventory_display_type = "EXTENSION_ATTRIBUTES"
  script_contents        = file("${path.module}/scripts/ea_splunk_mcp_status.sh")
}

# --- UPTIME ---
resource "jamfpro_computer_extension_attribute" "uptime" {
  name                   = "Uptime"
  description            = "Number of days since last restart"
  data_type              = "INTEGER"
  enabled                = true
  input_type             = "SCRIPT"
  inventory_display_type = "EXTENSION_ATTRIBUTES"
  script_contents        = file("${path.module}/scripts/ea_uptime.sh")
}

# --- NESSUS AGENT STATUS (TENABLE DECOMMISSION IN-479 / IN-484) ---
resource "jamfpro_computer_extension_attribute" "nessus_agent_status" {
  name                   = "Nessus Agent Status"
  description            = "Reports whether the Tenable Nessus Agent is present; drives the Nessus - Installed smart group for the IN-484 decommission"
  data_type              = "STRING"
  enabled                = true
  input_type             = "SCRIPT"
  inventory_display_type = "EXTENSION_ATTRIBUTES"
  script_contents        = file("${path.module}/scripts/ea_nessus_agent_status.sh")
}
