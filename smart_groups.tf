# --- CROWDSTRIKE WRONG CID ---

resource "jamfpro_smart_computer_group" "crowdstrike_wrong_cid" {
  name = "CrowdStrike - Wrong CID"

  criteria {
    name        = "CrowdStrike Sensor Status"
    priority    = 0
    search_type = "is"
    value       = "Wrong CID"
  }
}

# --- CROWDSTRIKE NOT RUNNING ---

resource "jamfpro_smart_computer_group" "crowdstrike_not_running" {
  name = "CrowdStrike - Not Running"

  criteria {
    name        = "CrowdStrike Sensor Status"
    priority    = 0
    search_type = "is"
    value       = "Not Running"
  }
}

# --- CROWDSTRIKE NOT INSTALLED ---

resource "jamfpro_smart_computer_group" "crowdstrike_not_installed" {
  name = "CrowdStrike - Not Installed"

  criteria {
    name        = "CrowdStrike Sensor Status"
    priority    = 0
    search_type = "is"
    value       = "Not Installed"
  }
}

# --- CROWDSTRIKE COMPLIANT ---

resource "jamfpro_smart_computer_group" "crowdstrike_compliant" {
  name = "CrowdStrike - Compliant"

  criteria {
    name        = "CrowdStrike Sensor Status"
    priority    = 0
    search_type = "is"
    value       = "Running"
  }
}

# --- DOCKER DESKTOP INSTALLED ---

resource "jamfpro_smart_computer_group" "docker_installed" {
  name = "Docker Desktop Installed"

  criteria {
    name        = "Application Title"
    search_type = "is"
    value       = "Docker.app"
    and_or      = "and"
    priority    = 0
  }
}

resource "jamfpro_smart_computer_group" "wireshark_installed" {
  name = "Wireshark Installed"

  criteria {
    name        = "Application Title"
    search_type = "is"
    value       = "Wireshark.app"
    and_or      = "and"
    priority    = 0
  }
}

# --- ENCRYPTION (FileVault) ---

resource "jamfpro_smart_computer_group" "filevault_enabled" {
  name = "FileVault - Enabled"
  criteria {
    name        = "FileVault 2 Partition Encryption State"
    priority    = 0
    and_or      = "and"
    search_type = "is"
    value       = "Encrypted"
  }
}

resource "jamfpro_smart_computer_group" "filevault_not_enabled" {
  name = "FileVault - Not Enabled"
  criteria {
    name        = "FileVault 2 Partition Encryption State"
    priority    = 0
    and_or      = "and"
    search_type = "is not"
    value       = "Encrypted"
  }
}

resource "jamfpro_smart_computer_group" "filevault_key_valid" {
  name = "FileVault - Key Valid"
  criteria {
    name        = "FileVault 2 Individual Key Validation"
    priority    = 0
    and_or      = "and"
    search_type = "is"
    value       = "Valid"
  }
}

resource "jamfpro_smart_computer_group" "filevault_key_invalid" {
  name = "FileVault - Key Invalid"
  criteria {
    name        = "FileVault 2 Individual Key Validation"
    priority    = 0
    and_or      = "and"
    search_type = "is not"
    value       = "Valid"
  }
  criteria {
    name        = "FileVault 2 Partition Encryption State"
    priority    = 1
    and_or      = "and"
    search_type = "is"
    value       = "Encrypted"
  }
}

resource "jamfpro_smart_computer_group" "filevault_compliant" {
  name = "FileVault - Compliant"
  criteria {
    name        = "FileVault 2 Partition Encryption State"
    priority    = 0
    and_or      = "and"
    search_type = "is"
    value       = "Encrypted"
  }
  criteria {
    name        = "FileVault 2 Individual Key Validation"
    priority    = 1
    and_or      = "and"
    search_type = "is"
    value       = "Valid"
  }
}

# --- ENDPOINT PROTECTION (CrowdStrike) ---

resource "jamfpro_smart_computer_group" "crowdstrike_installed" {
  name = "CrowdStrike - Installed"
  criteria {
    name        = "Application Title"
    priority    = 0
    and_or      = "and"
    search_type = "is"
    value       = "Falcon.app"
  }
}

resource "jamfpro_smart_computer_group" "crowdstrike_missing" {
  name = "CrowdStrike - Missing"
  criteria {
    name        = "Application Title"
    priority    = 0
    and_or      = "and"
    search_type = "does not have"
    value       = "Falcon.app"
  }
}

# --- FIREWALL ---

resource "jamfpro_smart_computer_group" "firewall_enabled" {
  name = "Firewall - Enabled"
  criteria {
    name        = "Firewall Enabled"
    priority    = 0
    and_or      = "and"
    search_type = "is"
    value       = "Enabled"
  }
}

resource "jamfpro_smart_computer_group" "firewall_disabled" {
  name = "Firewall - Disabled"
  criteria {
    name        = "Firewall Enabled"
    priority    = 0
    and_or      = "and"
    search_type = "is"
    value       = "Not Enabled"
  }
}

# --- GATEKEEPER & SIP ---

resource "jamfpro_smart_computer_group" "gatekeeper_enabled" {
  name = "Gatekeeper - Enabled"
  criteria {
    name        = "Gatekeeper"
    priority    = 0
    and_or      = "and"
    search_type = "is"
    value       = "App Store and identified developers"
  }
}

resource "jamfpro_smart_computer_group" "gatekeeper_disabled" {
  name = "Gatekeeper - Disabled or Weakened"
  criteria {
    name        = "Gatekeeper"
    priority    = 0
    and_or      = "and"
    search_type = "is not"
    value       = "App Store and identified developers"
  }
}

resource "jamfpro_smart_computer_group" "sip_enabled" {
  name = "SIP - Enabled"
  criteria {
    name        = "System Integrity Protection"
    priority    = 0
    and_or      = "and"
    search_type = "is"
    value       = "Enabled"
  }
}

resource "jamfpro_smart_computer_group" "sip_disabled" {
  name = "SIP - Disabled"
  criteria {
    name        = "System Integrity Protection"
    priority    = 0
    and_or      = "and"
    search_type = "is not"
    value       = "Enabled"
  }
}

# --- macOS VERSION COMPLIANCE ---

resource "jamfpro_smart_computer_group" "macos_sequoia" {
  name = "macOS - Sequoia (15.x)"
  criteria {
    name        = "Operating System Version"
    priority    = 0
    and_or      = "and"
    search_type = "like"
    value       = "15."
  }
}

resource "jamfpro_smart_computer_group" "macos_sonoma" {
  name = "macOS - Sonoma (14.x)"
  criteria {
    name        = "Operating System Version"
    priority    = 0
    and_or      = "and"
    search_type = "like"
    value       = "14."
  }
}

resource "jamfpro_smart_computer_group" "macos_tahoe" {
  name = "macOS - Tahoe (26.x)"
  criteria {
    name        = "Operating System Version"
    priority    = 0
    and_or      = "and"
    search_type = "like"
    value       = "26."
  }
}

resource "jamfpro_smart_computer_group" "macos_supported" {
  name = "macOS - Supported (14.0+)"
  criteria {
    name        = "Operating System Version"
    priority    = 0
    and_or      = "and"
    search_type = "greater than or equal"
    value       = "14.0"
  }
}

resource "jamfpro_smart_computer_group" "macos_unsupported" {
  name = "macOS - Unsupported (Below 14.0)"
  criteria {
    name        = "Operating System Version"
    priority    = 0
    and_or      = "and"
    search_type = "less than"
    value       = "14.0"
  }
}

resource "jamfpro_smart_computer_group" "macos_update_available" {
  name = "macOS - Update Available"
  criteria {
    name        = "Number of Available Updates"
    priority    = 0
    and_or      = "and"
    search_type = "more than"
    value       = "0"
  }
}

# --- DEVICE HEALTH & CHECK-IN ---

resource "jamfpro_smart_computer_group" "checkin_24h" {
  name = "Check-in - Last 24 Hours"
  criteria {
    name        = "Last Check-in"
    priority    = 0
    and_or      = "and"
    search_type = "less than x days ago"
    value       = "1"
  }
}

resource "jamfpro_smart_computer_group" "checkin_stale_7d" {
  name = "Check-in - Stale (7+ Days)"
  criteria {
    name        = "Last Check-in"
    priority    = 0
    and_or      = "and"
    search_type = "more than x days ago"
    value       = "7"
  }
}

resource "jamfpro_smart_computer_group" "checkin_stale_30d" {
  name = "Check-in - Stale (30+ Days)"
  criteria {
    name        = "Last Check-in"
    priority    = 0
    and_or      = "and"
    search_type = "more than x days ago"
    value       = "30"
  }
}

resource "jamfpro_smart_computer_group" "checkin_stale_90d" {
  name = "Check-in - Stale (90+ Days)"
  criteria {
    name        = "Last Check-in"
    priority    = 0
    and_or      = "and"
    search_type = "more than x days ago"
    value       = "90"
  }
}

resource "jamfpro_smart_computer_group" "disk_space_low" {
  name = "Disk Space - Low (<10GB)"
  criteria {
    name        = "Boot Drive Available MB"
    priority    = 0
    and_or      = "and"
    search_type = "less than"
    value       = "10240"
  }
}

resource "jamfpro_smart_computer_group" "disk_space_critical" {
  name = "Disk Space - Critical (<5GB)"
  criteria {
    name        = "Boot Drive Available MB"
    priority    = 0
    and_or      = "and"
    search_type = "less than"
    value       = "5120"
  }
}

# --- HARDWARE ARCHITECTURE ---

resource "jamfpro_smart_computer_group" "hw_apple_silicon" {
  name = "Hardware - Apple Silicon"
  criteria {
    name        = "Architecture Type"
    priority    = 0
    and_or      = "and"
    search_type = "is"
    value       = "ARM (Apple Silicon)"
  }
}

resource "jamfpro_smart_computer_group" "hw_intel" {
  name = "Hardware - Intel"
  criteria {
    name        = "Architecture Type"
    priority    = 0
    and_or      = "and"
    search_type = "is"
    value       = "x86_64"
  }
}

resource "jamfpro_smart_computer_group" "hw_laptop" {
  name = "Hardware - Laptops"
  criteria {
    name        = "Model"
    priority    = 0
    and_or      = "and"
    search_type = "like"
    value       = "MacBook"
  }
}

resource "jamfpro_smart_computer_group" "hw_desktop" {
  name = "Hardware - Desktops"
  criteria {
    name        = "Model"
    priority    = 0
    and_or      = "and"
    search_type = "not like"
    value       = "MacBook"
  }
}

# --- ENROLLMENT & MDM ---

resource "jamfpro_smart_computer_group" "mdm_capable" {
  name = "MDM - Capable"
  criteria {
    name        = "MDM Profile Expiration Date"
    priority    = 0
    and_or      = "and"
    search_type = "after (yyyy-mm-dd)"
    value       = "2020-01-01"
  }
}

resource "jamfpro_smart_computer_group" "enrolled_7d" {
  name = "Enrollment - Last 7 Days"
  criteria {
    name        = "Last Enrollment"
    priority    = 0
    and_or      = "and"
    search_type = "less than x days ago"
    value       = "7"
  }
}

resource "jamfpro_smart_computer_group" "enrolled_30d" {
  name = "Enrollment - Last 30 Days"
  criteria {
    name        = "Last Enrollment"
    priority    = 0
    and_or      = "and"
    search_type = "less than x days ago"
    value       = "30"
  }
}

resource "jamfpro_smart_computer_group" "user_approved_mdm" {
  name = "MDM - User Approved"
  criteria {
    name        = "User Approved MDM"
    priority    = 0
    and_or      = "and"
    search_type = "is"
    value       = "Yes"
  }
}

resource "jamfpro_smart_computer_group" "user_approved_mdm_no" {
  name = "MDM - Not User Approved"
  criteria {
    name        = "User Approved MDM"
    priority    = 0
    and_or      = "and"
    search_type = "is"
    value       = "No"
  }
}

# --- HOMEBREW DETECTED SMART GROUP ---
resource "jamfpro_smart_computer_group" "homebrew_detected" {
  name = "Computers with Unauthorized Homebrew"

  criteria {
    name        = "User Homebrew Installations"
    priority    = 0
    and_or      = "and"
    search_type = "is not"
    value       = "None"
  }
}

# --- HOMEBREW DAEMON NOT RUNNING SMART GROUP ---
# Jamf's "like"/"not like" is a substring match, not SQL LIKE — "%" is a
# literal character. The EA reports "Running (PID: n)" when healthy, so match
# that prefix; the unhealthy values ("Not Installed", "Not Running",
# "Loaded but not running") all lack it and stay in the group.
resource "jamfpro_smart_computer_group" "homebrew_daemon_not_running" {
  name = "Homebrew Daemon - Not Running"

  criteria {
    name        = "Homebrew Monitor Daemon Status"
    priority    = 0
    and_or      = "and"
    search_type = "not like"
    value       = "Running (PID"
  }
}

# --- HOMEBREW WEEKLY UPGRADE FAILING ---
# Driven by the "Homebrew Upgrade Status" EA. A device enters when its last
# weekly upgrade reported FAIL and leaves automatically once a later run is OK.
# Used by the daily compliance check for real root cause (no device access).
resource "jamfpro_smart_computer_group" "homebrew_upgrade_failing" {
  name = "Homebrew Upgrade - Failing"

  criteria {
    name        = "Homebrew Upgrade Status"
    priority    = 0
    and_or      = "and"
    search_type = "like"
    value       = "FAIL"
  }

  depends_on = [jamfpro_computer_extension_attribute.homebrew_upgrade_status]
}

# --- HOMEBREW PACKAGE INSTALL FAILING ---
# Driven by the "Homebrew Install Failures" EA. A device enters when any
# package's most recent install run failed; the Ongoing install policies retry
# every check-in, so the device leaves the group once the install succeeds.
# Matches "like FAIL" (the EA prefixes failures with "FAIL:") rather than
# "is not None" — otherwise devices with an empty/never-collected EA value
# would be wrongly included.
resource "jamfpro_smart_computer_group" "homebrew_install_failing" {
  name = "Homebrew Install - Failing"

  criteria {
    name        = "Homebrew Install Failures"
    priority    = 0
    and_or      = "and"
    search_type = "like"
    value       = "FAIL"
  }

  depends_on = [jamfpro_computer_extension_attribute.homebrew_install_failures]
}

# --- BOOTSTRAP TOKEN ---

resource "jamfpro_smart_computer_group" "bootstrap_escrowed" {
  name = "Bootstrap Token - Escrowed"
  criteria {
    name        = "Bootstrap Token Allowed"
    priority    = 0
    and_or      = "and"
    search_type = "is"
    value       = "Yes"
  }
}

resource "jamfpro_smart_computer_group" "bootstrap_not_escrowed" {
  name = "Bootstrap Token - Not Escrowed"
  criteria {
    name        = "Bootstrap Token Allowed"
    priority    = 0
    and_or      = "and"
    search_type = "is"
    value       = "No"
  }
}

# --- REMOTE DESKTOP / SCREEN SHARING ---

resource "jamfpro_smart_computer_group" "remote_desktop_enabled" {
  name = "Remote Desktop - Enabled"
  criteria {
    name        = "Remote Desktop Enabled"
    priority    = 0
    and_or      = "and"
    search_type = "is"
    value       = "Yes"
  }
}

# --- ACTIVATION LOCK ---

resource "jamfpro_smart_computer_group" "activation_lock_enabled" {
  name = "Activation Lock - Enabled"
  criteria {
    name        = "Activation Lock Enabled"
    priority    = 0
    and_or      = "and"
    search_type = "is"
    value       = "Yes"
  }
}

# --- RECOVERY LOCK ---

resource "jamfpro_smart_computer_group" "recovery_lock_enabled" {
  name = "Recovery Lock - Enabled"
  criteria {
    name        = "Recovery Lock Enabled"
    priority    = 0
    and_or      = "and"
    search_type = "is"
    value       = "Yes"
  }
}

resource "jamfpro_smart_computer_group" "recovery_lock_not_enabled_apple_silicon" {
  name = "Recovery Lock - Not Enabled (Apple Silicon)"
  criteria {
    name        = "Architecture Type"
    priority    = 0
    and_or      = "and"
    search_type = "is"
    value       = "ARM (Apple Silicon)"
  }
  criteria {
    name        = "Recovery Lock Enabled"
    priority    = 1
    and_or      = "and"
    search_type = "is not"
    value       = "Yes"
  }
}

# --- SOFTWARE - COMMON APPS ---

resource "jamfpro_smart_computer_group" "app_slack_installed" {
  name = "App - Slack Installed"
  criteria {
    name        = "Application Title"
    priority    = 0
    and_or      = "and"
    search_type = "is"
    value       = "Slack.app"
  }
}

resource "jamfpro_smart_computer_group" "app_zoom_installed" {
  name = "App - Zoom Installed"
  criteria {
    name        = "Application Title"
    priority    = 0
    and_or      = "and"
    search_type = "is"
    value       = "zoom.us.app"
  }
}

resource "jamfpro_smart_computer_group" "app_1password_installed" {
  name = "App - 1Password Installed"
  criteria {
    name        = "Application Title"
    priority    = 0
    and_or      = "and"
    search_type = "is"
    value       = "1Password.app"
  }
}

resource "jamfpro_smart_computer_group" "app_chrome_installed" {
  name = "App - Chrome Installed"
  criteria {
    name        = "Application Title"
    priority    = 0
    and_or      = "and"
    search_type = "is"
    value       = "Google Chrome.app"
  }
}

resource "jamfpro_smart_computer_group" "app_jamf_connect_installed" {
  name = "App - Jamf Connect Installed"
  criteria {
    name        = "Application Title"
    priority    = 0
    and_or      = "and"
    search_type = "is"
    value       = "Jamf Connect.app"
  }
}

# --- LOGI OPTIONS+ NOT INSTALLED ---
# install_logi_options.sh's own idempotency check is "does logioptionsplus.app
# exist" (it no longer writes to the Homebrew install-failure status files —
# that marker path was retired in #115 when the app moved off the Homebrew
# cask to a direct vendor-installer run; the script only clears a stale
# leftover marker). Native "Application Title" inventory criteria, matching
# the existing App - * Installed groups above, is therefore the only signal
# available to detect a device that still needs the install: it's in this
# group whenever the app isn't present, whether because the install never ran
# or because it ran and failed.
resource "jamfpro_smart_computer_group" "logi_options_not_installed" {
  name = "App - Logi Options+ Not Installed"
  criteria {
    name        = "Application Title"
    priority    = 0
    and_or      = "and"
    search_type = "is not"
    value       = "logioptionsplus.app"
  }
}

# --- XPROTECT ---

resource "jamfpro_smart_computer_group" "xprotect_current" {
  name = "XProtect - Current"
  criteria {
    name        = "XProtect Definitions Version"
    priority    = 0
    and_or      = "and"
    search_type = "greater than or equal"
    value       = "5300"
  }
}

# --- BATTERY HEALTH (Laptops) ---

resource "jamfpro_smart_computer_group" "battery_degraded" {
  name = "Battery - Degraded"
  criteria {
    name        = "Model"
    priority    = 0
    and_or      = "and"
    search_type = "like"
    value       = "MacBook"
  }
  criteria {
    name        = "Battery Health"
    priority    = 1
    and_or      = "and"
    search_type = "is not"
    value       = "Normal"
  }
}

# --- COMPLIANCE ROLLUP GROUPS ---

resource "jamfpro_smart_computer_group" "compliance_security_baseline" {
  name = "Compliance - Security Baseline Met"
  criteria {
    name        = "FileVault 2 Partition Encryption State"
    priority    = 0
    and_or      = "and"
    search_type = "is"
    value       = "Encrypted"
  }
  criteria {
    name        = "Firewall Enabled"
    priority    = 1
    and_or      = "and"
    search_type = "is"
    value       = "Enabled"
  }
  criteria {
    name        = "Gatekeeper"
    priority    = 2
    and_or      = "and"
    search_type = "is"
    value       = "App Store and identified developers"
  }
  criteria {
    name        = "System Integrity Protection"
    priority    = 3
    and_or      = "and"
    search_type = "is"
    value       = "Enabled"
  }
  criteria {
    name        = "Operating System Version"
    priority    = 4
    and_or      = "and"
    search_type = "greater than or equal"
    value       = "13.0"
  }
}

resource "jamfpro_smart_computer_group" "compliance_security_baseline_failed" {
  name = "Compliance - Security Baseline NOT Met"
  criteria {
    name        = "FileVault 2 Partition Encryption State"
    priority    = 0
    and_or      = "and"
    search_type = "is not"
    value       = "Encrypted"
  }
  criteria {
    name        = "Firewall Enabled"
    priority    = 1
    and_or      = "or"
    search_type = "is"
    value       = "Not Enabled"
  }
  criteria {
    name        = "Gatekeeper"
    priority    = 2
    and_or      = "or"
    search_type = "is"
    value       = "Off"
  }
  criteria {
    name        = "System Integrity Protection"
    priority    = 3
    and_or      = "or"
    search_type = "is not"
    value       = "Enabled"
  }
  criteria {
    name        = "Operating System Version"
    priority    = 4
    and_or      = "or"
    search_type = "less than"
    value       = "13.0"
  }
}

# --- SECURE TOKEN SMART GROUPS ---

# Computers WITH Secure Token
resource "jamfpro_smart_computer_group" "secure_token_enabled" {
  name = "Secure Token - Enabled"

  criteria {
    name        = "Secure Token Status"
    priority    = 0
    and_or      = "and"
    search_type = "is not"
    value       = "None"
  }

  depends_on = [jamfpro_computer_extension_attribute.secure_token_status]
}

# Computers WITHOUT Secure Token
resource "jamfpro_smart_computer_group" "secure_token_missing" {
  name = "Secure Token - Missing"

  criteria {
    name        = "Secure Token Status"
    priority    = 0
    and_or      = "and"
    search_type = "is"
    value       = "None"
  }

  depends_on = [jamfpro_computer_extension_attribute.secure_token_status]
}

# Smart group for targeting Setup Manager

resource "jamfpro_smart_computer_group" "setup_manager_target" {
  name = "Setup Manager Target"

  criteria {
    name        = "Serial Number"
    search_type = "like"
    value       = ""
    and_or      = "and"
    priority    = 0
  }
}

# --- SPLUNK UNIVERSAL FORWARDER ---

resource "jamfpro_smart_computer_group" "splunk_inputs_needs_update" {
  name = "Splunk UF - Inputs Needs Update"

  criteria {
    name        = "Splunk Inputs Script Version"
    priority    = 0
    and_or      = "and"
    search_type = "is not"
    value       = local.splunk_inputs_script_hash
  }

  depends_on = [jamfpro_computer_extension_attribute.splunk_inputs_version]
}

# Devices that HAVE Splunk UF installed but are not on the pinned target version.
# Fresh installs ("Not Installed") are excluded — those are handled by the
# "Once per computer" install policy. This group scopes the Ongoing upgrade
# policy, so a device leaves the group automatically once it reports the target.
resource "jamfpro_smart_computer_group" "splunk_uf_needs_upgrade" {
  name = "Splunk UF - Needs Upgrade"

  criteria {
    name        = "Splunk UF Version"
    priority    = 0
    and_or      = "and"
    search_type = "is not"
    value       = local.splunk_target_version
  }

  criteria {
    name        = "Splunk UF Version"
    priority    = 1
    and_or      = "and"
    search_type = "is not"
    value       = "Not Installed"
  }

  depends_on = [jamfpro_computer_extension_attribute.splunk_uf_version]
}

# Devices whose last Splunk UF install/upgrade run FAILED, per the "Splunk UF
# Status" EA. Scopes the Ongoing "Splunk UF - Remediate Failed Install" policy:
# because the install policy is "Once per computer", a failed first run would
# otherwise stay Failed forever. This group + Ongoing remediation retries every
# check-in and the device leaves the group once a run reports OK.
resource "jamfpro_smart_computer_group" "splunk_uf_needs_remediation" {
  name = "Splunk UF - Needs Remediation"

  criteria {
    name        = "Splunk UF Status"
    priority    = 0
    and_or      = "and"
    search_type = "like"
    value       = "FAIL"
  }

  depends_on = [jamfpro_computer_extension_attribute.splunk_uf_status]
}

# Devices where Splunk REJECTS the deployed MCP token (HTTP 401/403), per the
# "Splunk MCP Status" EA. This is a visibility / alerting group, NOT an
# auto-remediation target: a rejected token is fixed by rotating the
# SPLUNK_MCP_TOKEN secret and re-applying, not by re-running a policy on the
# Mac. UNREACHABLE (offline / off-network) and NO_CONFIG are deliberately
# excluded so laptops that simply cannot reach Splunk do not read as failures.
resource "jamfpro_smart_computer_group" "splunk_mcp_auth_failing" {
  name = "Splunk MCP - Auth Failing"

  criteria {
    name        = "Splunk MCP Status"
    priority    = 0
    and_or      = "and"
    search_type = "is"
    value       = "AUTH_FAIL"
  }

  depends_on = [jamfpro_computer_extension_attribute.splunk_mcp_status]
}

# --- VS CODE PATH SMART GROUP ---
resource "jamfpro_smart_computer_group" "vscode_installed" {
  name = "Computers with VS Code Installed"

  criteria {
    name        = "Application Title"
    search_type = "is"
    value       = "Visual Studio Code.app"
    priority    = 0
  }
}

# --- TENABLE NESSUS AGENT (DECOMMISSION IN-479 / IN-484) ---
# Driven by the "Nessus Agent Status" EA. A device enters when the agent is
# present and leaves automatically once the Ongoing removal policy has stripped
# it, so the removal policy self-limits and is a safe no-op everywhere else.
resource "jamfpro_smart_computer_group" "nessus_installed" {
  name = "Nessus - Installed"

  criteria {
    name        = "Nessus Agent Status"
    priority    = 0
    and_or      = "and"
    search_type = "is"
    value       = "Installed"
  }

  depends_on = [jamfpro_computer_extension_attribute.nessus_agent_status]
}
