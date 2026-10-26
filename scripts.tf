resource "jamfpro_script" "install_homebrew_srv_root" {
  name            = "Install Homebrew for srv_root"
  script_contents = file("${path.module}/scripts/install_homebrew_srv_root.sh")
  category_id     = jamfpro_category.terraform_managed.id
  priority        = "AFTER"
}

# --- JAMF CONNECT LOGIN PLUGIN VERSION ENFORCEMENT ---
# The login plugin ships in the static JamfConnectLogin.pkg and does not
# auto-update, and its install policy is only triggered by Setup Manager at
# provisioning — so already-enrolled Macs never receive a newer plugin. These two
# scripts close that gap and then clear the stale keychain ACL that keeps
# Self Service+ prompting for the login keychain password.
resource "jamfpro_script" "update_jamf_connect_login" {
  name            = "Jamf Connect Login - Ensure Minimum Version"
  script_contents = file("${path.module}/scripts/update_jamf_connect_login.sh")
  category_id     = jamfpro_category.terraform_managed.id
  priority        = "AFTER"
  info            = "Compares the installed Jamf Connect login plugin against a minimum version and fires the install-jamfconnect event if it is short. Parameter 4 = minimum version, parameter 5 = install event."
  notes           = "No-op once the plugin meets the minimum, so it is safe fleet-wide on an Ongoing policy. Exits 0 on failure and records status instead, to avoid flagging every check-in as Failed."
}

resource "jamfpro_script" "reset_jamf_connect_keychain" {
  name            = "Jamf Connect - Reset Keychain ACL"
  script_contents = file("${path.module}/scripts/reset_jamf_connect_keychain.sh")
  category_id     = jamfpro_category.terraform_managed.id
  priority        = "AFTER"
  info            = "Deletes the stale 'Jamf Connect' login-keychain item so the updated plugin recreates it with Self Service+ in the ACL. Parameter 4 = minimum plugin version."
  notes           = "A keychain item's ACL is stamped at creation and never retro-fitted, so updating the plugin alone does not stop the prompt. Runs automatically after the version-check script in the 'Ensure Minimum Version' policy. Skips unless the plugin already meets the minimum and a console user is logged in; one-shot per user per plugin version."
}

resource "jamfpro_script" "install_xcode_cli_tools" {
  name            = "Install xcode CLI tools"
  script_contents = file("${path.module}/scripts/install_xcode_cli_tools.sh")
  category_id     = jamfpro_category.terraform_managed.id
  priority        = "AFTER"
}

resource "jamfpro_script" "install_rosetta" {
  name            = "Install Rosetta"
  script_contents = file("${path.module}/scripts/install_rosetta.sh")
  category_id     = jamfpro_category.terraform_managed.id
  priority        = "BEFORE"
}

resource "jamfpro_script" "filevault_reissue_key" {
  name            = "FileVault - Reissue Recovery Key"
  category_id     = jamfpro_category.terraform_managed.id
  priority        = "AFTER"
  info            = "Reissues the FileVault personal recovery key for machines with invalid escrow."
  script_contents = file("${path.module}/scripts/filevault_reissue_key.sh")
}

resource "jamfpro_script" "install_splunk_uf" {
  name            = "Splunk UF - Install"
  category_id     = jamfpro_category.terraform_managed.id
  priority        = "AFTER"
  script_contents = file("${path.module}/scripts/install_splunk_uf.sh")
  info            = "Installs/upgrades Splunk UF (darwin-arm64) with Splunk Cloud credentials for example.splunkcloud.com. Parameter 4 = target version, parameter 5 = download URL."
}

# --- PAPERCUT HIVE ---

resource "jamfpro_script" "deploy_papercut_hive" {
  name            = "PaperCut edge node & Print Client"
  category_id     = jamfpro_category.terraform_managed.id
  priority        = "AFTER"
  info            = "Installs PaperCut Hive edge node and Print Client from cached zip package"
  script_contents = file("${path.module}/scripts/deploy_papercut_hive.sh")
}

# --- ANACONDA ---

resource "jamfpro_script" "install_anaconda" {
  name            = "Anaconda - Install and Configure"
  category_id     = jamfpro_category.terraform_managed.id
  priority        = "AFTER"
  info            = "Installs Anaconda via Homebrew and runs conda init zsh for the logged-in user"
  script_contents = file("${path.module}/scripts/install_anaconda.sh")
}

# --- CROWDSTRIKE MANAGEMENT SCRIPT ---

resource "jamfpro_script" "manage_crowdstrike" {
  name            = "CrowdStrike - Manage"
  category_id     = jamfpro_category.terraform_managed.id
  priority        = "AFTER"
  info            = "Unified lifecycle: checks operational+CID, applies CID if wrong, installs pkg via jamf policy event if not installed. Parameter 4 = CID."
  script_contents = file("${path.module}/scripts/manage_crowdstrike.sh")
}

# --- WIRESHARK ---

resource "jamfpro_script" "install_wireshark" {
  name            = "Wireshark - Install and Configure"
  priority        = "AFTER"
  script_contents = file("${path.module}/scripts/install_wireshark.sh")
  category_id     = jamfpro_category.terraform_managed.id
  info            = "Installs Wireshark via Homebrew cask and configures ChmodBPF for packet capture without sudo"
}

resource "jamfpro_script" "install_logi_options" {
  name            = "Logi Options+ - Install"
  priority        = "AFTER"
  script_contents = file("${path.module}/scripts/install_logi_options.sh")
  category_id     = jamfpro_category.terraform_managed.id
  info            = "Installs Logitech Options+ by running the vendor's silent installer as root (the logi-options+ Homebrew cask can't run in our non-root brew pipeline)."
}

# --- DOCKER DESKTOP CONFIGURATION SCRIPT ---

resource "jamfpro_script" "configure_docker" {
  name            = "Configure Docker Desktop Privileged Helper"
  priority        = "AFTER"
  script_contents = file("${path.module}/scripts/configure_docker.sh")
  category_id     = jamfpro_category.terraform_managed.id
  info            = "Installs Docker Desktop privileged helper to prevent admin prompts"
}

# --- INSTALL HOMEBREW MONITOR DAEMON ---
resource "jamfpro_script" "install_homebrew_monitor_daemon" {
  name            = "Install Homebrew Monitor Daemon"
  priority        = "AFTER"
  script_contents = file("${path.module}/scripts/install_homebrew_monitor_daemon.sh")
  category_id     = -1
  info            = "Installs and configures the Homebrew monitoring LaunchDaemon"
  notes           = "Deploys daemon that scans every 60 seconds and blocks unauthorized Homebrew installations"
}

# --- CONFIGURE SPLUNK UA ---

locals {
  splunk_inputs_script_hash = substr(sha256(file("${path.module}/scripts/configure_splunk_inputs.sh")), 0, 12)

  # --- SPLUNK UF TARGET VERSION (single source of truth) ---
  # The fleet is entirely Apple Silicon, so we target the darwin-arm64 build.
  # The download filename embeds an unpredictable per-build hash that cannot be
  # derived from the version, so the full URL is pinned here, not constructed.
  # This version drives BOTH the install/upgrade script (passed as parameters 4
  # and 5 by the policies) and the "Needs Upgrade" smart group criteria, so a
  # device is upgraded exactly when its reported version != splunk_target_version.
  #
  # To roll the fleet to a new release: scrape the new arm64 URL from
  # https://www.splunk.com/en_us/download/universal-forwarder.html and update
  # BOTH values below (and the matching defaults in scripts/install_splunk_uf.sh).
  splunk_target_version = "10.4.3"
  splunk_target_url     = "https://download.splunk.com/products/universalforwarder/releases/10.4.3/osx/splunkforwarder-10.4.3-4174a2deda5d-darwin-arm64.tgz"
}

resource "jamfpro_script" "configure_splunk_inputs" {
  name        = "Splunk UF - Configure Inputs"
  category_id = jamfpro_category.terraform_managed.id
  priority    = "AFTER"
  info        = "Configures Splunk UF inputs. Version: ${local.splunk_inputs_script_hash}"

  # Changed from file() to templatefile() to inject version
  script_contents = templatefile("${path.module}/scripts/configure_splunk_inputs.sh", {
    script_version = local.splunk_inputs_script_hash
  })
}

# --- CHECK PARTICULARS LOCATION PERMISSION ---
resource "jamfpro_script" "check_particulars_location" {
  name            = "Check Particulars Location Permission"
  priority        = "AFTER"
  script_contents = file("${path.module}/scripts/check_particulars_location.sh")
  category_id     = jamfpro_category.terraform_managed.id
  info            = "Checks if Particulars has location permission and prompts if not"
  notes           = "Run on recurring schedule until user grants permission"
}

# --- DISABLE DESKTOP WIDGETS ---
resource "jamfpro_script" "disable_widgets" {
  name            = "Disable Desktop Widgets"
  priority        = "AFTER"
  script_contents = file("${path.module}/scripts/disable_widgets.sh")
  category_id     = jamfpro_category.terraform_managed.id
  info            = "Disables macOS desktop widgets"
  notes           = "Hides widgets from desktop and Stage Manager"
}

# --- DISABLE SCREEN SAVER ---
resource "jamfpro_script" "disable_screensaver" {
  name            = "Disable Screen Saver"
  priority        = "AFTER"
  script_contents = file("${path.module}/scripts/disable_screensaver.sh")
  category_id     = jamfpro_category.terraform_managed.id
  info            = "Disables screen saver for logged-in user"
  notes           = "Sets idleTime to 0"
}

# --- DUO DESKTOP ---

resource "jamfpro_script" "install_duo_desktop" {
  name            = "Duo Desktop - Install"
  category_id     = jamfpro_category.terraform_managed.id
  priority        = "AFTER"
  info            = "Downloads and installs Duo Desktop from Duo's CDN; allows Duo to manage its own certificate and auto-updates"
  script_contents = file("${path.module}/scripts/install_duo_desktop.sh")
}

# --- ENABLE TIME SYNC ---

resource "jamfpro_script" "enable_time_sync" {
  name            = "Enable Automatic Time Sync"
  priority        = "AFTER"
  script_contents = file("${path.module}/scripts/enable_time_sync.sh")
  category_id     = jamfpro_category.terraform_managed.id
  info            = "Enables automatic date/time sync with Apple time servers"
  notes           = ""
}

# --- EXAMPLE IT TOOLING SCRIPT ---
resource "jamfpro_script" "example_it_tooling" {
  name            = "Example IT Tooling Installer"
  priority        = "AFTER"
  script_contents = file("${path.module}/scripts/example_it_tooling.sh")
  category_id     = -1
  info            = "Installs all Example developer CLI tools via Homebrew"
  notes           = "Includes: kubectl, helm, go, node, rust, mongosh, and more"
}

# --- FIX NPM GLOBAL PREFIX ---
resource "jamfpro_script" "fix_npm_global_prefix" {
  name            = "Fix npm Global Prefix"
  priority        = "AFTER"
  script_contents = file("${path.module}/scripts/fix_npm_global_prefix.sh")
  category_id     = jamfpro_category.terraform_managed.id
  info            = "Configures npm global prefix to ~/.npm-global so users can npm install -g without admin"
  notes           = "Fixes EACCES errors from homebrew_srv-owned node_modules"
}

# --- FIX NODE.JS CA CERTIFICATES ---
resource "jamfpro_script" "fix_node_ca_certs" {
  name            = "Fix Node.js CA Certificates"
  priority        = "AFTER"
  script_contents = file("${path.module}/scripts/fix_node_ca_certs.sh")
  category_id     = jamfpro_category.terraform_managed.id
  info            = "Exports macOS system trusted CAs and configures npm/Node.js to use them"
  notes           = "Fixes UNABLE_TO_GET_ISSUER_CERT_LOCALLY errors"
}

# --- FIX HOME DIRECTORY PERMISSIONS ---
resource "jamfpro_script" "fix_home_directory_permissions" {
  name            = "Fix Home Directory Permissions"
  priority        = "AFTER"
  script_contents = file("${path.module}/scripts/fix_home_directory_permissions.sh")
  category_id     = jamfpro_category.terraform_managed.id
  info            = "Fixes ownership and permissions for the current user's home directory"
  notes           = "Sets user as owner of all files, home directory permissions to 750"
}

# --- HOMEBREW PACKAGE INSTALLER SCRIPT ---
resource "jamfpro_script" "homebrew_installer" {
  name            = "Homebrew Package Installer"
  priority        = "AFTER"
  script_contents = file("${path.module}/scripts/homebrew_package_installer.sh")
  category_id     = -1
  info            = "Installs packages via Homebrew for the srv_mac user"
  notes           = "Parameters: $4=formula/cask token, $5=tap (optional), $6=type 'formula' (default) or 'cask'"
}

resource "jamfpro_script" "install_gcloud_cli_with_setup" {
  name            = "Install Google Cloud CLI (with setup)"
  priority        = "AFTER"
  script_contents = file("${path.module}/scripts/install_gcloud_cli_with_setup.sh")
  category_id     = jamfpro_category.terraform_managed.id
  info            = "Installs gcloud, fixes Node.js CA certs, and fixes home directory permissions in one script"
}

# --- INSTALL KUBECTL SCRIPT ---
resource "jamfpro_script" "install_kubectl" {
  name            = "Install kubectl"
  priority        = "AFTER"
  script_contents = file("${path.module}/scripts/install_kubectl.sh")
  category_id     = -1
  info            = "Installs kubectl for Kubernetes cluster management"
  notes           = "Downloads latest stable version, supports Intel and Apple Silicon"
}

# --- INTERACTIVE SCHEDULED REBOOT ---
resource "jamfpro_script" "scheduled_reboot_interactive" {
  name            = "Schedule Reboot - Interactive"
  priority        = "AFTER"
  script_contents = file("${path.module}/scripts/scheduled_reboot_interactive.sh")
  category_id     = jamfpro_category.terraform_managed.id
  info            = "Prompts user to reboot 8 hours after enrollment with snooze option"
  notes           = "User can postpone up to 3 times (1 hour each)"
}

# --- INSTALL/UPDATE PODMAN CLI SCRIPT ---
resource "jamfpro_script" "install_podman" {
  name            = "Install or Update Podman CLI"
  priority        = "AFTER"
  script_contents = file("${path.module}/scripts/install_podman.sh")
  category_id     = -1
  info            = "Installs or updates Podman CLI from GitHub releases"
  notes           = "Installs if missing, updates if newer version available"
}

# --- SECURE TOKEN VERIFICATION ---
resource "jamfpro_script" "verify_secure_token" {
  name            = "Verify Secure Token Status"
  priority        = "AFTER"
  script_contents = file("${path.module}/scripts/verify_secure_token.sh")
  category_id     = jamfpro_category.terraform_managed.id
  info            = "Reports Secure Token status for all local user accounts"
  notes           = "Exits 0 if at least one account has Secure Token, exits 1 if none"
}

# --- WALLPAPER DEPLOYMENT ---
resource "jamfpro_script" "set_wallpaper" {
  name            = "Deploy Example Wallpaper"
  priority        = "AFTER"
  script_contents = file("${path.module}/scripts/set_wallpaper.sh")
  category_id     = jamfpro_category.terraform_managed.id
  info            = "Sets Example corporate wallpaper for logged-in user"
  notes           = "Requires Example-Wallpaper package to be installed first"
}

# --- UPGRADE HOMEBREW PACKAGES SCRIPT ---
resource "jamfpro_script" "upgrade_homebrew_packages" {
  name            = "Upgrade Homebrew Packages"
  priority        = "AFTER"
  script_contents = file("${path.module}/scripts/upgrade_homebrew_packages.sh")
  category_id     = jamfpro_category.terraform_managed.id
  info            = "Upgrades all Homebrew packages installed under /opt/homebrew_srv"
  notes           = "Runs brew update, brew upgrade, and brew cleanup"
}

# --- UPDATE GCLOUD CLI SCRIPT ---
resource "jamfpro_script" "update_gcloud_cli" {
  name            = "Update Google Cloud CLI"
  priority        = "AFTER"
  script_contents = file("${path.module}/scripts/update_gcloud_cli.sh")
  category_id     = -1
  info            = "Updates Google Cloud SDK to the latest version"
  notes           = "Skips if gcloud not installed"
}

# --- UPDATE KUBECTL SCRIPT ---
resource "jamfpro_script" "update_kubectl" {
  name            = "Update kubectl"
  priority        = "AFTER"
  script_contents = file("${path.module}/scripts/update_kubectl.sh")
  category_id     = -1
  info            = "Updates kubectl to the latest stable version"
  notes           = "Skips if kubectl not installed or already at latest"
}

# --- VS CODE PATH CONFIGURATION ---
resource "jamfpro_script" "vscode_path" {
  name            = "Add VS Code to PATH"
  priority        = "AFTER"
  script_contents = file("${path.module}/scripts/vscode_path.sh")
  category_id     = jamfpro_category.terraform_managed.id
  info            = "Adds VS Code bin directory to system PATH via /etc/paths.d"
  notes           = "Allows users to run 'code' command without admin privileges"
}

# --- ADD TO DEVELOPER GROUP ---
resource "jamfpro_script" "add_to_developer_group" {
  name            = "Add User to Developer Tools Group"
  category_id     = jamfpro_category.terraform_managed.id
  priority        = "AFTER"
  info            = "Adds the logged-in user to the macOS _developer group, allowing debugging without admin credentials"
  script_contents = file("${path.module}/scripts/add_to_developer_group.sh")
}

resource "jamfpro_script" "reset_loom_tcc" {
  name            = "Reset Loom TCC Accessibility"
  category_id     = jamfpro_category.terraform_managed.id
  priority        = "AFTER"
  info            = "Resets Loom's TCC Accessibility entry so the MDM PPPC profile can re-apply it correctly"
  script_contents = file("${path.module}/scripts/reset_loom_tcc.sh")
}

# --- SET JAMF PRO USERNAME FROM JAMF CONNECT ---

resource "jamfpro_script" "set_jamf_username" {
  name            = "Set Jamf Username from Jamf Connect"
  category_id     = jamfpro_category.terraform_managed.id
  priority        = "AFTER"
  info            = "Reads :DisplayName from the Jamf Connect state plist for the console user and writes it to Jamf Pro via `jamf recon -endUsername`."
  script_contents = file("${path.module}/scripts/set_jamf_username.sh")
}

# --- SPLUNK MCP SERVER CONFIG ---
resource "jamfpro_script" "configure_splunk_mcp" {
  name            = "Splunk MCP - Configure for Claude Code"
  priority        = "AFTER"
  script_contents = file("${path.module}/scripts/configure_splunk_mcp.sh")
  category_id     = jamfpro_category.terraform_managed.id
  info            = "Writes the Splunk MCP server entry into Claude Code's system-level enterprise managed config at /Library/Application Support/ClaudeCode/managed-mcp.json (root-owned, applies to every user). Parameter 4 = endpoint, parameter 5 = encrypted token."
  notes           = "Merges JSON rather than calling `claude mcp add`, so the token never appears in the process list and the write is atomic. Also sets allowAllClaudeAiMcps in managed-settings.json to preserve claude.ai connectors (set MCP_EXCLUSIVE=1 to lock down to managed servers only). System-level, so no console-user dependency — it applies to all users and works before anyone logs in. Fails (exit 1) only when the endpoint/token parameters are missing or an existing managed JSON file is not valid JSON."
}

# --- TENABLE NESSUS AGENT REMOVAL (IN-479 / IN-484) ---
# Tenable decommission: uninstalls the Nessus Agent, which was deployed outside
# Terraform. Idempotent and a safe no-op when the agent is absent, so it is
# harmless anywhere it runs.
resource "jamfpro_script" "remove_nessus_agent" {
  name            = "Nessus Agent - Remove"
  category_id     = jamfpro_category.terraform_managed.id
  priority        = "AFTER"
  info            = "Uninstalls the Tenable Nessus Agent (unlink, remove launch daemon/service, delete /Library/NessusAgent and the preference pane, forget pkg receipts) for the IN-484 Tenable decommission. Jamf parameters 1-3 (mount/host/user) are unused."
  notes           = "Idempotent and a safe no-op when the agent is absent (exits 0 with nothing to remove), so it is harmless fleet-wide. Paired with the 'Nessus - Installed' smart group so machines drop out of scope as the agent is removed (Jira IN-479 / IN-484)."
  script_contents = file("${path.module}/scripts/remove_nessus_agent.sh")
}
