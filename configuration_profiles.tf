# --- JAMF CHECK-IN RECON DAEMON ---

resource "jamfpro_macos_configuration_profile_plist" "checkin_recon_daemon" {
  name                = "Jamf Check-in Recon Daemon"
  description         = "Runs jamf policy and recon at 09:00 and 21:00 daily."
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/profiles/checkin_recon_daemon.mobileconfig")

  scope {
    all_computers = true
  }
}

# --- CROWDSTRIKE ---

resource "jamfpro_macos_configuration_profile_plist" "crowdstrike_falcon" {
  name                = "Crowdstrike Falcon Profile"
  description         = "CrowdStrike Falcon sensor system extension and network filter configuration"
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/profiles/crowdstrike_falcon.mobileconfig")

  scope {
    all_computers = true
  }
}

# --- CURSOR - DISABLE AUTO UPDATES ---

resource "jamfpro_macos_configuration_profile_plist" "cursor_settings" {
  name                = "Cursor - Disable Auto Updates"
  description         = "Disables Cursor auto-updates to prevent privileged helper prompts. Updates managed via Jamf."
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/profiles/cursor_settings.mobileconfig")

  scope {
    all_computers = true
  }
}

# --- ITERM2 - DISABLE AUTO UPDATES ---

resource "jamfpro_macos_configuration_profile_plist" "iterm2_settings" {
  name                = "iTerm2 - Disable Auto Updates"
  description         = "Disables iTerm2 auto-updates to prevent privileged helper prompts. Updates managed via Jamf."
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/profiles/iterm2_settings.mobileconfig")

  scope {
    all_computers = true
  }
}

# --- DOCK CONFIGURATION ---

resource "jamfpro_macos_configuration_profile_plist" "dock_configuration" {
  name                = "Dock Configuration"
  description         = "Configures dock settings and default apps for Example"
  level               = "System"
  distribution_method = "Install Automatically"
  redeploy_on_update  = "All"
  category_id         = jamfpro_category.terraform_managed.id

  payloads = file("${path.module}/profiles/dock_configuration.mobileconfig")

  scope {
    all_computers = true
  }
}

# --- FIREWALL ---

resource "jamfpro_macos_configuration_profile_plist" "firewall" {
  name                = "Security - Firewall"
  description         = "Enables macOS firewall with stealth mode."
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  # Real payload is GUI-managed; ignore_changes below means this placeholder is
  # never pushed to the existing profile. It only lets a from-empty CI plan
  # validate (the provider requires the top-level Payload* keys).
  payloads = file("${path.module}/profiles/security_firewall_placeholder.mobileconfig")

  scope {
    all_computers = true
  }

  lifecycle {
    ignore_changes = [payloads]
  }
}

# --- FILEVAULT ---

resource "jamfpro_macos_configuration_profile_plist" "filevault" {
  name                = "Security - FileVault"
  description         = "Enforces FileVault disk encryption with deferred enablement."
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  # Real payload is GUI-managed; ignore_changes below means this placeholder is
  # never pushed to the existing profile. It only lets a from-empty CI plan
  # validate (the provider requires the top-level Payload* keys).
  payloads = file("${path.module}/profiles/security_filevault_placeholder.mobileconfig")

  scope {
    all_computers = true
  }
  #This actual config can only be managed in the GUI. This will break all machines if you try to manage with TF
  lifecycle {
    ignore_changes = [payloads]
  }
}

# --- DISPLAYLINK SETTINGS ---

resource "jamfpro_macos_configuration_profile_plist" "displaylink_settings" {
  name                = "DisplayLink Manager Settings"
  description         = "Pre-configures DisplayLink Manager settings"
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/profiles/displaylink_settings.mobileconfig")

  scope {
    all_computers = true
  }
}

# --- GATEKEEPER ---

resource "jamfpro_macos_configuration_profile_plist" "gatekeeper" {
  name                = "Security - Gatekeeper"
  description         = "Enforces Gatekeeper to allow only App Store and identified developers."
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/profiles/gatekeeper.mobileconfig")

  scope {
    all_computers = true
  }
}

# --- JAMF CONNECT ---

resource "jamfpro_macos_configuration_profile_plist" "jamf_connect_license" {
  name                = "Jamf Connect - License"
  description         = "Jamf Connect license configuration for Okta integration"
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/profiles/jamf_connect_license.mobileconfig")

  scope {
    all_computers = true
  }
}

resource "jamfpro_macos_configuration_profile_plist" "jamf_connect_login" {
  name                = "Jamf Connect - Login"
  description         = "Jamf Connect Login window configuration for Okta authentication"
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/profiles/jamf_connect_login.mobileconfig")

  scope {
    all_computers = true
  }
}

resource "jamfpro_macos_configuration_profile_plist" "jamf_connect_menubar" {
  name                = "Jamf Connect - Menubar"
  description         = "Jamf Connect menubar app configuration for password sync"
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/profiles/jamf_connect_menubar.mobileconfig")

  scope {
    all_computers = true
  }
}

# --- LOGIN WINDOW ---

resource "jamfpro_macos_configuration_profile_plist" "login_window" {
  name                = "Security - Login Window"
  description         = "Hardens login window: disables guest account, shows name/password fields, displays legal banner, and prevents automatic login."
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/profiles/login_window.mobileconfig")

  scope {
    all_computers = true
  }
}

# --- PARTICULARS CONFIGURATION ---

resource "jamfpro_macos_configuration_profile_plist" "particulars" {
  name                = "Particulars Configuration"
  description         = "Configures Particulars system info display for Example"
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/profiles/particulars.mobileconfig")

  scope {
    all_computers = true
  }
}

# --- PPPC - ALFRED ACCESSIBILITY ---

resource "jamfpro_macos_configuration_profile_plist" "pppc_alfred" {
  name                = "PPPC - Alfred"
  description         = "Grants Accessibility permission to Alfred 5"
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/profiles/pppc_alfred.mobileconfig")

  scope {
    all_computers = true
  }
}

# --- PPPC - CLAUDE ACCESSIBILITY ---

resource "jamfpro_macos_configuration_profile_plist" "pppc_claude" {
  name                = "PPPC - Claude"
  description         = "Grants Accessibility permission to Claude"
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/profiles/pppc_claude.mobileconfig")

  scope {
    all_computers = true
  }
}

# --- PPPC - LOOM ACCESSIBILITY ---

resource "jamfpro_macos_configuration_profile_plist" "pppc_loom_accessibility" {
  name                = "PPPC - Loom Accessibility"
  description         = "Grants Accessibility permission to Loom"
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/profiles/pppc_loom_accessibility.mobileconfig")

  scope {
    all_computers = true
  }

  # Jamf re-serialises the payload on store — it reassigns its own PayloadUUID/
  # PayloadIdentifier, syncs PayloadDisplayName to the profile name, injects
  # PayloadEnabled, and escapes quotes in the code requirements. The repo file
  # can therefore never byte-match what Jamf returns, so every plan showed a
  # perpetual (functionally no-op) diff. Ignore payload drift here — same pattern
  # as the firewall/filevault profiles. To intentionally change Loom's PPPC
  # permissions, edit the .mobileconfig and temporarily remove this block.
  lifecycle {
    ignore_changes = [payloads]
  }
}

# --- PPPC - LOGI OPTIONS+ ACCESSIBILITY ---

resource "jamfpro_macos_configuration_profile_plist" "pppc_logi_options_accessibility" {
  name                = "PPPC - Logi Options+ Accessibility"
  description         = "Grants Accessibility to Logi Options+ (main app and the cp-dev-mgr agent) so users aren't prompted after install"
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/profiles/pppc_logi_options_accessibility.mobileconfig")

  scope {
    all_computers = true
  }
}

# --- PPPC - SCREEN RECORDING, CAMERA, MICROPHONE ---

resource "jamfpro_macos_configuration_profile_plist" "pppc_screen_recording" {
  name                = "PPPC - Screen Recording, Camera, Microphone"
  description         = "Pre-approves screen recording, camera, and microphone permissions for communication apps"
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/profiles/pppc_screen_recording.mobileconfig")

  scope {
    all_computers = true
  }
}

# --- PPPC - JAMF SYSTEM EVENTS ACCESS ---

resource "jamfpro_macos_configuration_profile_plist" "pppc_jamf_system_events" {
  name                = "Privacy - Jamf System Events Access"
  description         = "Allows Jamf agent to control System Events for scripting"
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/profiles/pppc_jamf_system_events.mobileconfig")

  scope {
    all_computers = true
  }
}

# --- PPPC - ITERM2 FULL DISK ACCESS ---

resource "jamfpro_macos_configuration_profile_plist" "pppc_iterm_fda" {
  name                = "PPPC - iTerm2 Full Disk Access"
  description         = "Grants Full Disk Access to iTerm2"
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/profiles/pppc_iterm_fda.mobileconfig")

  scope {
    all_computers = true
  }
}

# --- RESTRICTIONS - APPLE INTELLIGENCE ---

resource "jamfpro_macos_configuration_profile_plist" "restrictions_apple_intelligence" {
  name                = "Restrictions - Apple Intelligence"
  description         = "Controls Apple Intelligence features. Blocks Mail AI and external AI integrations (ChatGPT) on macOS 15+."
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/profiles/restrictions_apple_intelligence.mobileconfig")

  scope {
    all_computers = true
  }
}

# --- RESTRICTIONS - APPLICATIONS ---

resource "jamfpro_macos_configuration_profile_plist" "restrictions_applications" {
  name                = "Restrictions - Applications"
  description         = "Controls Game Center, iPhone Mirroring, Safari settings, and App Store behavior."
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/profiles/restrictions_applications.mobileconfig")

  scope {
    all_computers = true
  }
}

# --- RESTRICTIONS - FUNCTIONALITY ---

resource "jamfpro_macos_configuration_profile_plist" "restrictions_functionality" {
  name                = "Restrictions - Functionality"
  description         = "Controls AirDrop, AirPrint, passwords, continuity features, and system modifications."
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/profiles/restrictions_functionality.mobileconfig")

  scope {
    all_computers = true
  }
}

# --- RESTRICTIONS - ICLOUD ---

resource "jamfpro_macos_configuration_profile_plist" "restrictions_icloud" {
  name                = "Restrictions - iCloud"
  description         = "Controls iCloud services to prevent corporate data leakage. Disables iCloud Drive, Keychain, Mail, Calendar, and Contacts."
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/profiles/restrictions_icloud.mobileconfig")

  scope {
    all_computers = true
  }
}

# --- RESTRICTIONS - SHARING SERVICES ---

resource "jamfpro_macos_configuration_profile_plist" "restrictions_sharing_services" {
  name                = "Restrictions - Sharing Services"
  description         = "Controls Share menu services and prevents modification of Bluetooth, File, Internet, and Remote Management sharing."
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/profiles/restrictions_sharing_services.mobileconfig")

  scope {
    all_computers = true
  }
}

# --- RESTRICTIONS - SOFTWARE UPDATE ---

resource "jamfpro_macos_configuration_profile_plist" "restrictions_software_update" {
  name                = "Restrictions - Software Update Deferral"
  description         = "Defers major OS updates by 14 days and app updates by 7 days. Rapid Security Responses are not deferred."
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/profiles/restrictions_software_update.mobileconfig")

  scope {
    all_computers = true
  }
}

# --- RESTRICTIONS - SYSTEM PREFERENCES ---

resource "jamfpro_macos_configuration_profile_plist" "restrictions_system_preferences" {
  name                = "Restrictions - System Preferences"
  description         = "Restricts access to sensitive System Settings panes including Users & Groups, Profiles, Sharing, Startup Disk, and Time Machine."
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/profiles/restrictions_system_preferences.mobileconfig")

  scope {
    all_computers = true
  }
}

# --- SCREEN LOCK ---

resource "jamfpro_macos_configuration_profile_plist" "screen_lock" {
  name                = "Security - Screen Lock"
  description         = "Enforces screen lock after 5 minutes of inactivity and requires password immediately upon wake."
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/profiles/screen_lock.mobileconfig")

  scope {
    all_computers = true
  }
}

# --- SETUP MANAGER ---

resource "jamfpro_macos_configuration_profile_plist" "setup_manager" {
  name                = "Example Setup Manager"
  description         = "Setup Manager configuration for zero-touch Mac deployment"
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/profiles/setup_manager.mobileconfig")

  scope {
    all_computers = true
  }

  lifecycle {
    ignore_changes = [payloads]
  }
}

# --- SPLUNK UNIVERSAL FORWARDER FDA ---

resource "jamfpro_macos_configuration_profile_plist" "splunk_fda" {
  name                = "Splunk Universal Forwarder - Full Disk Access"
  description         = "Grants FDA to Splunk UF for reading system logs, audit logs, and Jamf logs"
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/profiles/splunk_fda.mobileconfig")

  scope {
    all_computers = true
  }
}

# --- TAILSCALE SYSTEM EXTENSION ---

resource "jamfpro_macos_configuration_profile_plist" "tailscale_system_extension" {
  name                = "Tailscale - System Extension"
  description         = "Allows Tailscale Network Extension without user approval"
  level               = "System"
  distribution_method = "Install Automatically"
  redeploy_on_update  = "Newly Assigned"
  category_id         = jamfpro_category.terraform_managed.id

  payloads = file("${path.module}/profiles/tailscale_system_extension.mobileconfig")

  scope {
    all_computers = true
  }
}

