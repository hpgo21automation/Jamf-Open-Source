# --- DUO DESKTOP ---

resource "jamfpro_policy" "install_duo_desktop" {
  name                        = "Duo Desktop - Install"
  enabled                     = true
  trigger_checkin             = true
  trigger_enrollment_complete = true
  frequency                   = "Once per computer"
  category_id                 = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    scripts {
      id       = jamfpro_script.install_duo_desktop.id
      priority = "After"
    }
  }
}

# --- PAPERCUT HIVE ---

resource "jamfpro_policy" "deploy_papercut_hive" {
  name                        = "Install and Deploy PaperCut Hive"
  enabled                     = true
  trigger_checkin             = true
  trigger_enrollment_complete = true
  trigger_login               = true
  frequency                   = "Once per computer"
  category_id                 = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    packages {
      distribution_point = "default"
      package {
        id     = 14 # papercut-hive.zip
        action = "Cache"
      }
    }

    scripts {
      id       = jamfpro_script.deploy_papercut_hive.id
      priority = "After"
    }
  }
}

# --- ANACONDA ---

resource "jamfpro_policy" "install_anaconda" {
  name        = "Install Anaconda"
  enabled     = true
  frequency   = "Ongoing"
  category_id = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    scripts {
      id       = jamfpro_script.install_anaconda.id
      priority = "After"
    }
  }

  self_service {
    use_for_self_service      = true
    feature_on_main_page      = false
    self_service_display_name = "Anaconda"
    self_service_description  = "Installs Anaconda and configures conda for your account"
    install_button_text       = "Install"
    reinstall_button_text     = "Reinstall"
  }
}

# --- CROWDSTRIKE ---
# manage_crowdstrike.sh handles the full lifecycle: checks operational+CID,
# applies CID if wrong, triggers a package-install helper via custom event
# if not installed. No package payload here — BEFORE scripts cannot gate
# package execution in Jamf, so all install logic lives in the script.

resource "jamfpro_policy" "install_crowdstrike_falcon" {
  name                        = "Manage CrowdStrike Falcon"
  enabled                     = true
  trigger_checkin             = true
  trigger_enrollment_complete = true
  frequency                   = "Ongoing"
  category_id                 = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    scripts {
      id         = jamfpro_script.manage_crowdstrike.id
      priority   = "After"
      parameter4 = var.crowdstrike_cid
      parameter5 = var.crowdstrike_provisioning_token
    }
  }

  self_service {
    use_for_self_service            = false
    feature_on_main_page            = false
    force_users_to_view_description = false
    notification                    = false
    notification_type               = "Self Service"
    notification_subject            = "Manage CrowdStrike Falcon"
    install_button_text             = "Install"
    reinstall_button_text           = "Reinstall"
    self_service_icon_id            = 0
  }
}

# --- WIRESHARK ---

resource "jamfpro_policy" "install_wireshark" {
  name        = "Wireshark - Install and Configure"
  enabled     = true
  frequency   = "Ongoing"
  category_id = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    scripts {
      id       = jamfpro_script.install_wireshark.id
      priority = "After"
    }
  }

  self_service {
    use_for_self_service      = true
    feature_on_main_page      = false
    self_service_display_name = "Wireshark"
    self_service_description  = "Installs Wireshark and configures BPF permissions for packet capture"
    install_button_text       = "Install"
    reinstall_button_text     = "Reinstall"
  }
}

# --- LOGITECH OPTIONS+ ---
# Delivered via a root-run vendor installer rather than Homebrew: the
# logi-options+ cask invokes its installer through interactive `sudo`, which
# fails in the non-root srv_mac brew pipeline. Jamf runs this script as root,
# so the silent installer works directly.
resource "jamfpro_policy" "install_logi_options" {
  name        = "Install Logi Options+"
  enabled     = true
  frequency   = "Ongoing"
  category_id = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    scripts {
      id       = jamfpro_script.install_logi_options.id
      priority = "After"
    }
    # Recon right after the run so the "Homebrew Install Failures" EA
    # re-evaluates immediately and the device leaves the failing smart group
    # without waiting for the next scheduled inventory update.
    maintenance {
      recon = true
    }
  }

  self_service {
    use_for_self_service      = true
    feature_on_main_page      = false
    self_service_display_name = "Logi Options+"
    self_service_description  = "Installs Logitech Options+ for configuring Logitech mice and keyboards. A reboot is recommended after install."
    install_button_text       = "Install"
    reinstall_button_text     = "Reinstall"
  }
}

# --- LOGI OPTIONS+ REMEDIATION POLICY ---
# "Install Logi Options+" above is Self Service-only, so a device whose
# install fails (or that never ran it) stays that way until a human opens
# Self Service. This Ongoing policy is scoped to the "App - Logi Options+ Not
# Installed" smart group and reruns the same idempotent script every
# check-in until the app is present, at which point the device leaves the
# group. Mirrors remediate_homebrew_daemon's checkin-retry pattern below.
resource "jamfpro_policy" "remediate_logi_options" {
  name            = "Remediate Logi Options+ Install"
  enabled         = true
  trigger_checkin = true
  frequency       = "Ongoing"
  category_id     = jamfpro_category.terraform_managed.id

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.logi_options_not_installed.id]
  }

  payloads {
    scripts {
      id       = jamfpro_script.install_logi_options.id
      priority = "After"
    }
    maintenance {
      recon = true
    }
  }
}

# --- DOCKER DESKTOP PRIVILEGED HELPER ---

resource "jamfpro_policy" "configure_docker_desktop" {
  name            = "Configure Docker Desktop Privileged Helper"
  enabled         = true
  trigger_checkin = true
  frequency       = "Once per computer"
  category_id     = jamfpro_category.terraform_managed.id

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.docker_installed.id]
  }

  payloads {
    scripts {
      id       = jamfpro_script.configure_docker.id
      priority = "After"
    }
    maintenance {
      recon = true
    }
  }
}

# --- DISABLE DESKTOP WIDGETS ---

resource "jamfpro_policy" "disable_widgets" {
  name                        = "Disable Desktop Widgets"
  enabled                     = true
  trigger_login               = true
  trigger_checkin             = false
  trigger_enrollment_complete = true
  frequency                   = "Ongoing"
  category_id                 = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    scripts {
      id       = jamfpro_script.disable_widgets.id
      priority = "After"
    }
  }
}

# --- SET JAMF USERNAME ON LOGIN ---
# Keeps the Jamf Pro device record's "End Username" field in sync with the
# logged-in user, via the Jamf Connect DisplayName plist.

resource "jamfpro_policy" "set_jamf_username" {
  name          = "Set Jamf Username from Jamf Connect"
  enabled       = true
  trigger_login = true
  frequency     = "Ongoing"
  category_id   = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    scripts {
      id       = jamfpro_script.set_jamf_username.id
      priority = "After"
    }
  }
}

# --- DISABLE SCREEN SAVER ---

resource "jamfpro_policy" "disable_screensaver" {
  name                        = "Disable Screen Saver"
  enabled                     = true
  trigger_login               = true
  trigger_checkin             = false
  trigger_enrollment_complete = true
  frequency                   = "Ongoing"
  category_id                 = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    scripts {
      id       = jamfpro_script.disable_screensaver.id
      priority = "After"
    }
  }
}

# --- FILEVAULT ---

resource "jamfpro_policy" "filevault_key_remediation" {
  name            = "FileVault - Reissue Recovery Key"
  enabled         = true
  trigger_checkin = true
  frequency       = "Once per computer"
  category_id     = jamfpro_category.terraform_managed.id

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.filevault_key_invalid.id]
  }

  payloads {
    scripts {
      id       = jamfpro_script.filevault_reissue_key.id
      priority = "Before"
    }
    maintenance {
      recon = true
    }
  }

  self_service {
    use_for_self_service            = false
    feature_on_main_page            = false
    force_users_to_view_description = false
    notification                    = false
    notification_type               = "Self Service and Notification Center"
    notification_subject            = "Security Action Required. Please do not ignore."
    install_button_text             = "Install"
    reinstall_button_text           = "Reinstall"
    self_service_icon_id            = 0
  }
}

# --- SELF SERVICE: FIX HOME DIRECTORY PERMISSIONS ---
resource "jamfpro_policy" "self_service_fix_home_permissions" {
  name        = "Fix Home Directory Permissions"
  enabled     = true
  frequency   = "Ongoing"
  category_id = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    scripts {
      id       = jamfpro_script.fix_home_directory_permissions.id
      priority = "After"
    }
  }

  self_service {
    use_for_self_service            = true
    feature_on_main_page            = true
    force_users_to_view_description = false
    self_service_display_name       = "Fix Home Directory Permissions"
    self_service_description        = "Fixes ownership and permissions for your home directory. Use this if you're experiencing permission errors accessing files in your home folder."
    install_button_text             = "Fix Permissions"
    reinstall_button_text           = "Fix Permissions"
  }
}

# --- SELF SERVICE: EXAMPLE IT TOOLING ---
resource "jamfpro_policy" "self_service_example_it_tooling" {
  name        = "Example IT Tooling"
  enabled     = true
  frequency   = "Ongoing"
  category_id = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    scripts {
      id       = jamfpro_script.example_it_tooling.id
      priority = "After"
    }
    scripts {
      id       = jamfpro_script.fix_home_directory_permissions.id
      priority = "After"
    }
  }

  self_service {
    use_for_self_service            = true
    feature_on_main_page            = true
    force_users_to_view_description = true
    self_service_display_name       = "Example IT Tooling"
    install_button_text             = "Install"
    reinstall_button_text           = "Reinstall"
    self_service_description = trimspace(<<-EOT
Installs the complete Example IT toolkit.

Cloud & Infrastructure:
mongodb-atlas-cli, cloud-sql-proxy, docker-credential-gcloud, opentofu

Kubernetes:
helm, helmfile, k6, kubectl, kubectx, kubens, kube-ps1, kustomize

Databases:
clickhouse, dbmate, mongosh

Languages & Runtimes:
bun, go, golangci-lint, micromamba, node, nvm, rust, rustup, uv

Dev Tools:
auth0, delve, gomplate, grpcurl, jira-cli

Networking:
haproxy, socat
EOT
    )
  }
}

# --- HOMEBREW ---

resource "jamfpro_policy" "deploy_homebrew" {
  name            = "Deploy Homebrew (srv_mac)"
  enabled         = true
  trigger_checkin = true
  trigger_other   = "install-homebrew"
  frequency       = "Once per computer"
  category_id     = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    scripts {
      id       = jamfpro_script.install_homebrew_srv_root.id
      priority = "Before"
    }
  }

  self_service {
    use_for_self_service            = false
    feature_on_main_page            = false
    force_users_to_view_description = false
    notification                    = false
    notification_type               = "Self Service"
    notification_subject            = "Deploy Homebrew (srv_mac)"
    install_button_text             = "Install"
    reinstall_button_text           = "Reinstall"
    self_service_icon_id            = 0
  }
}

# --- DEPLOY HOMEBREW MONITOR DAEMON POLICY ---
resource "jamfpro_policy" "deploy_homebrew_monitor" {
  name            = "Deploy Homebrew Monitor Daemon"
  enabled         = true
  trigger_checkin = true
  frequency       = "Once per computer"
  category_id     = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    scripts {
      id       = jamfpro_script.install_homebrew_monitor_daemon.id
      priority = "After"
    }
    maintenance {
      recon = true
    }
  }
}

# --- INTERACTIVE REBOOT POST ENROLLMENT ---

resource "jamfpro_policy" "scheduled_reboot_interactive" {
  name                        = "Schedule Reboot - Post Enrollment (Interactive)"
  enabled                     = true
  trigger_enrollment_complete = true
  trigger_checkin             = false
  frequency                   = "Once per computer"
  category_id                 = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    scripts {
      id       = jamfpro_script.scheduled_reboot_interactive.id
      priority = "After"
    }
  }
}

# --- INVENTORY ---

resource "jamfpro_policy" "update_inventory" {
  name            = "Update Inventory"
  enabled         = true
  trigger_checkin = true
  frequency       = "Once every week"
  category_id     = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    maintenance {
      recon = true
    }
  }
}

# --- JAMF ---

resource "jamfpro_policy" "force_jamf_checkin" {
  name        = "Force Jamf Check-in"
  enabled     = true
  frequency   = "Ongoing"
  category_id = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    files_processes {
      run_command = "/usr/local/bin/jamf policy && /usr/local/bin/jamf recon"
    }
  }

  self_service {
    use_for_self_service      = true
    feature_on_main_page      = true
    self_service_display_name = "Force Jamf Check-in"
    self_service_description  = "Forces your Mac to check in with Jamf and run any pending policies."
    install_button_text       = "Checkin"
    reinstall_button_text     = "Checkin"
    notification_subject      = "Force Jamf Check-in"
  }
}

locals {
  # First Jamf Connect login plugin release that honours
  # SharedTokenTrustedApplications for Self Service+, per Jamf's KB on the
  # "Self Service+ wants to use your confidential information stored in
  # 'Jamf Connect'" prompt. Drives both policies below.
  #
  # This is a *minimum*, compared numerically by the scripts — deliberately not an
  # exact-match smart group on the "Jamf Connect - Connect Login Plugin Version"
  # EA, because that EA is a STRING and Jamf would compare lexically, ordering
  # 3.25 below 3.6.
  jamf_connect_login_min_version = "3.6"
}

# --- JAMF CONNECT LOGIN PLUGIN UPGRADE + KEYCHAIN ACL RESET ---
# "Install Jamf Connect" below is triggered only by Setup Manager at
# provisioning, so it cannot deliver plugin updates to enrolled machines — which
# is why the fleet sits on a plugin too old to honour
# SharedTokenTrustedApplications, and why Self Service+ keeps prompting for the
# login keychain password.
#
# Both halves of the fix run here. NOTE the script order below is deliberate and
# looks backwards: Jamf does not preserve the payload order Terraform sends. It
# stored these reversed (reset id 58 first, then update id 57) and reports them
# that way, so listing them in Terraform's "logical" order produces a permanent
# plan diff. They are listed here in Jamf's storage order so plans stay clean.
#
# The consequence is that the reset runs BEFORE the upgrade on any given
# check-in. That is safe rather than broken, because the reset script refuses to
# act while the plugin is below the minimum — it would otherwise recreate the
# keychain item with the same broken ACL. So a Mac on an old plugin does:
#   check-in 1: reset skips (plugin still old) -> upgrade installs new plugin
#   check-in 2: reset now proceeds and clears the stale item
# i.e. it self-corrects one cycle later rather than in a single pass.
#
# Both scripts are cheap no-ops once a Mac is current (a version compare, then a
# marker-file check), so this is safe fleet-wide on an Ongoing trigger.
resource "jamfpro_policy" "upgrade_jamf_connect_login" {
  name            = "Jamf Connect Login - Ensure Minimum Version"
  enabled         = true
  trigger_checkin = true
  frequency       = "Ongoing"
  category_id     = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    # Listed in Jamf's storage order (see note above), not logical order.
    # Deletes the stale "Jamf Connect" keychain item so the plugin recreates it
    # with Self Service+ in the ACL. Self-guards on plugin version, and is
    # one-shot per user per plugin version so users are not re-prompted.
    scripts {
      id         = jamfpro_script.reset_jamf_connect_keychain.id
      priority   = "After"
      parameter4 = local.jamf_connect_login_min_version
    }
    scripts {
      id         = jamfpro_script.update_jamf_connect_login.id
      priority   = "After"
      parameter4 = local.jamf_connect_login_min_version
      parameter5 = "install-jamfconnect"
    }
    # No `maintenance { recon = true }` here, deliberately. Jamf rejects the
    # creation outright with 409 FIELD_INVENTORY_DANGER when a policy is
    # check-in triggered AND Ongoing AND scoped to all computers AND runs recon
    # — that combination means every Mac submits inventory on every check-in,
    # which is an inventory storm. Every other recon policy in this file breaks
    # at least one of those four; this one had all of them.
    #
    # The "Connect Login Plugin Version" EA therefore refreshes on the normal
    # inventory cycle rather than immediately. That is fine: the daily
    # compliance check is the consumer, and it runs well after check-in.
  }
}

resource "jamfpro_policy" "install_jamfconnect" {
  name          = "Install Jamf Connect"
  enabled       = true
  trigger_other = "install-jamfconnect"
  frequency     = "Ongoing"
  category_id   = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    packages {
      distribution_point = "default"
      package {
        id     = 1 # JamfConnectLogin.pkg
        action = "Install"
      }
    }
  }
}

# --- DEPLOY PARTICULARS ---

resource "jamfpro_policy" "deploy_particulars" {
  name                        = "Deploy Particulars"
  enabled                     = true
  trigger_checkin             = true
  trigger_enrollment_complete = true
  frequency                   = "Once per computer"
  category_id                 = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    packages {
      distribution_point = "default"
      package {
        id     = 7 # Particulars-68.485.pkg
        action = "Install"
      }
    }
  }
}

# --- HOMEBREW DAEMON REMEDIATION POLICY ---
resource "jamfpro_policy" "remediate_homebrew_daemon" {
  name            = "Remediate Homebrew Monitor Daemon"
  enabled         = true
  trigger_checkin = true
  frequency       = "Ongoing"
  category_id     = jamfpro_category.terraform_managed.id

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.homebrew_daemon_not_running.id]
  }

  payloads {
    scripts {
      id       = jamfpro_script.install_homebrew_monitor_daemon.id
      priority = "After"
    }
    maintenance {
      recon = true
    }
  }
}

# --- PARTICULARS LOCATION CHECK - RECURRING ---

resource "jamfpro_policy" "check_particulars_location" {
  name            = "Check Particulars Location Permission"
  enabled         = true
  trigger_checkin = true
  trigger_login   = true
  frequency       = "Once every day"
  category_id     = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    scripts {
      id       = jamfpro_script.check_particulars_location.id
      priority = "After"
    }
  }
}

# --- PPPC - RAZER SYNAPSE ---

resource "jamfpro_macos_configuration_profile_plist" "pppc_razer_synapse" {
  name                = "PPPC - Razer Synapse"
  description         = "Grants Input Monitoring and Accessibility permissions to Razer Synapse"
  level               = "System"
  category_id         = jamfpro_category.terraform_managed.id
  distribution_method = "Install Automatically"
  user_removable      = false
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/profiles/pppc_razer_synapse.mobileconfig")

  scope {
    all_computers = true
  }
}

# --- ROSETTA ---

resource "jamfpro_policy" "install_rosetta" {
  name                        = "Install Rosetta"
  enabled                     = true
  trigger_enrollment_complete = true
  trigger_checkin             = true
  frequency                   = "Once per computer"
  category_id                 = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    scripts {
      id       = jamfpro_script.install_rosetta.id
      priority = "Before"
    }
  }
}

# --- SCHEDULED UPGRADE HOMEBREW PACKAGES POLICY ---
resource "jamfpro_policy" "scheduled_upgrade_homebrew" {
  name            = "Upgrade Homebrew Packages (Weekly)"
  enabled         = true
  trigger_checkin = true
  frequency       = "Once every week"
  category_id     = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    scripts {
      id       = jamfpro_script.upgrade_homebrew_packages.id
      priority = "After"
    }
  }
}

# --- SCHEDULED WEEKLY UPDATERS (for_each over a map of tool → script) ---
# Each entry produces one Jamf policy that fires weekly at check-in and runs
# the matching script. To add a new tool, append to the map below; the policy
# is created automatically. To remove one, delete its entry.

locals {
  scheduled_updates = {
    gcloud_cli = {
      name      = "Update Google Cloud CLI (Weekly)"
      script_id = jamfpro_script.update_gcloud_cli.id
    }
    kubectl = {
      name      = "Update kubectl (Weekly)"
      script_id = jamfpro_script.update_kubectl.id
    }
    podman = {
      name      = "Update Podman CLI (Weekly)"
      script_id = jamfpro_script.install_podman.id
    }
  }
}

resource "jamfpro_policy" "scheduled_update" {
  for_each = local.scheduled_updates

  name            = each.value.name
  enabled         = true
  trigger_checkin = true
  frequency       = "Once every week"
  category_id     = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    scripts {
      id       = each.value.script_id
      priority = "After"
    }
  }
}

# --- FIX NPM GLOBAL PREFIX (ONE-TIME) ---
resource "jamfpro_policy" "fix_npm_global_prefix" {
  name            = "Fix npm Global Prefix"
  enabled         = true
  trigger_checkin = true
  trigger_login   = true
  frequency       = "Once per computer"
  category_id     = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    scripts {
      id       = jamfpro_script.fix_npm_global_prefix.id
      priority = "After"
    }
  }
}

# --- FIX NODE.JS CA CERTIFICATES (ONE-TIME) ---
resource "jamfpro_policy" "fix_node_ca_certs" {
  name            = "Fix Node.js CA Certificates"
  enabled         = true
  trigger_checkin = true
  frequency       = "Once per computer"
  category_id     = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    scripts {
      id       = jamfpro_script.fix_node_ca_certs.id
      priority = "After"
    }
  }
}

# --- SELF SERVICE: INSTALL GCLOUD CLI ---
resource "jamfpro_policy" "self_service_gcloud_cli" {
  name        = "Install Google Cloud CLI"
  enabled     = true
  frequency   = "Ongoing"
  category_id = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    scripts {
      id       = jamfpro_script.install_gcloud_cli_with_setup.id
      priority = "After"
    }
  }

  self_service {
    use_for_self_service      = true
    feature_on_main_page      = true
    self_service_display_name = "Google Cloud CLI"
    self_service_description  = "Installs the Google Cloud SDK (gcloud) for interacting with GCP resources from the command line."
    install_button_text       = "Install"
    reinstall_button_text     = "Reinstall"
  }
}

# --- SELF SERVICE: INSTALL LENS (Kubernetes IDE) ---
resource "jamfpro_policy" "install_lens" {
  name          = "Install Lens"
  enabled       = true
  trigger_other = "USER_INITIATED"
  frequency     = "Ongoing"
  category_id   = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    packages {
      distribution_point = "default"
      package {
        id     = var.lens_package_id
        action = "Install"
      }
    }
  }

  self_service {
    use_for_self_service      = true
    self_service_display_name = "Lens"
    self_service_description  = "Kubernetes IDE for managing clusters, viewing logs, and debugging applications."
    install_button_text       = "Install"
    reinstall_button_text     = "Reinstall"
    feature_on_main_page      = false
  }
}

# --- SELF SERVICE: INSTALL KUBECTL ---
resource "jamfpro_policy" "self_service_kubectl" {
  name        = "Install Kubectl"
  enabled     = true
  frequency   = "Ongoing"
  category_id = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    scripts {
      id       = jamfpro_script.fix_home_directory_permissions.id
      priority = "After"
    }
    scripts {
      id       = jamfpro_script.install_kubectl.id
      priority = "After"
    }
  }

  self_service {
    use_for_self_service      = true
    feature_on_main_page      = true
    self_service_display_name = "Kubectl"
    self_service_description  = "Installs kubectl for managing Kubernetes clusters."
    install_button_text       = "Install"
    reinstall_button_text     = "Reinstall"
  }
}

# --- SELF SERVICE: INSTALL/UPDATE PODMAN CLI ---
resource "jamfpro_policy" "self_service_podman" {
  name        = "Install Podman CLI"
  enabled     = true
  frequency   = "Ongoing"
  category_id = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    scripts {
      id       = jamfpro_script.install_podman.id
      priority = "After"
    }
  }

  self_service {
    use_for_self_service      = true
    feature_on_main_page      = true
    self_service_display_name = "Podman CLI"
    self_service_description  = "Installs or updates Podman CLI for running containers."
    install_button_text       = "Install"
    reinstall_button_text     = "Update"
  }
}

# --- SELF SERVICE: INSTALL RAZER SYNAPSE ---

resource "jamfpro_policy" "install_razer_synapse" {
  name          = "Install Razer Synapse"
  enabled       = true
  trigger_other = "USER_INITIATED"
  frequency     = "Ongoing"
  category_id   = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    packages {
      distribution_point = "default"
      package {
        id     = 9 # RazerSynapseInstaller.pkg
        action = "Install"
      }
    }
  }

  self_service {
    use_for_self_service      = true
    self_service_display_name = "Razer Synapse"
    self_service_description  = "Configure your Razer peripherals including mice, keyboards, and headsets."
    install_button_text       = "Install"
    reinstall_button_text     = "Reinstall"
    feature_on_main_page      = false
  }
}

# --- SECURE TOKEN VERIFICATION POLICY ---

resource "jamfpro_policy" "verify_secure_token" {
  name                        = "Verify Secure Token Status"
  enabled                     = true
  trigger_checkin             = true
  trigger_enrollment_complete = true
  frequency                   = "Once per computer"
  category_id                 = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    scripts {
      id       = jamfpro_script.verify_secure_token.id
      priority = "After"
    }
  }
}

# --- SELF SERVICE: INSTALL WISPR FLOW ---
resource "jamfpro_policy" "install_wispr_flow" {
  name          = "Install Wispr Flow"
  enabled       = true
  trigger_other = "USER_INITIATED"
  frequency     = "Ongoing"
  category_id   = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    packages {
      distribution_point = "default"
      package {
        id     = 12 # WisprFlow-1.4.227.pkg
        action = "Install"
      }
    }
  }

  self_service {
    use_for_self_service      = true
    self_service_display_name = "Wispr Flow"
    self_service_description  = "Voice-to-text dictation app. Speak naturally and Flow transcribes in real-time."
    install_button_text       = "Install"
    reinstall_button_text     = "Reinstall"
    feature_on_main_page      = false
  }
}

# --- SPLUNK UF INSTALLATION POLICY ---

resource "jamfpro_policy" "install_splunk_uf" {
  name            = "Splunk UF - Install"
  enabled         = true
  category_id     = jamfpro_category.terraform_managed.id
  trigger_checkin = true
  frequency       = "Once per computer"

  scope {
    all_computers = true
  }

  payloads {
    packages {
      distribution_point = "default"
      package {
        id     = 6 # SplunkCloudCredentials-Example-1.1.pkg
        action = "Install"
      }
    }
    scripts {
      id         = jamfpro_script.install_splunk_uf.id
      priority   = "After"
      parameter4 = local.splunk_target_version
      parameter5 = local.splunk_target_url
    }
    maintenance {
      recon = true
    }
  }
}

# --- SPLUNK UF UPGRADE POLICY ---
# "Splunk UF - Install" above is "Once per computer" and will not re-run on
# already-installed devices, so it cannot deliver version upgrades. This Ongoing
# policy is scoped to the "Needs Upgrade" smart group (installed version !=
# target) and runs the same script, which performs an in-place upgrade.
resource "jamfpro_policy" "upgrade_splunk_uf" {
  name            = "Splunk UF - Upgrade"
  enabled         = true
  category_id     = jamfpro_category.terraform_managed.id
  trigger_checkin = true
  frequency       = "Ongoing"

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.splunk_uf_needs_upgrade.id]
  }

  payloads {
    scripts {
      id         = jamfpro_script.install_splunk_uf.id
      priority   = "After"
      parameter4 = local.splunk_target_version
      parameter5 = local.splunk_target_url
    }
    maintenance {
      recon = true
    }
  }
}

# --- SPLUNK UF REMEDIATION POLICY ---
# "Splunk UF - Install" is "Once per computer" and exits 1 on failure, so a
# device whose first install fails (e.g. the credentials package step failed)
# stays permanently Failed until receipts are manually flushed. This Ongoing
# policy is scoped to the "Needs Remediation" smart group (last run reported
# FAIL via the "Splunk UF Status" EA) and re-runs the full install — including
# the credentials package payload — every check-in until a run reports OK, at
# which point the device leaves the group. Decouples remediation from Jamf's
# sticky policy-completion status.
resource "jamfpro_policy" "remediate_splunk_uf" {
  name            = "Splunk UF - Remediate Failed Install"
  enabled         = true
  category_id     = jamfpro_category.terraform_managed.id
  trigger_checkin = true
  frequency       = "Ongoing"

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.splunk_uf_needs_remediation.id]
  }

  payloads {
    packages {
      distribution_point = "default"
      package {
        id     = 6
        action = "Install"
      }
    }
    scripts {
      id         = jamfpro_script.install_splunk_uf.id
      priority   = "After"
      parameter4 = local.splunk_target_version
      parameter5 = local.splunk_target_url
    }
    maintenance {
      recon = true
    }
  }
}

# --- SPLUNK UF CONFIGURE INPUTS POLICY ---

resource "jamfpro_policy" "configure_splunk_inputs" {
  name            = "Splunk UF - Configure Inputs"
  enabled         = true
  category_id     = jamfpro_category.terraform_managed.id
  trigger_checkin = true
  frequency       = "Ongoing"

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.splunk_inputs_needs_update.id]
  }

  payloads {
    scripts {
      id       = jamfpro_script.configure_splunk_inputs.id
      priority = "After"
    }
    maintenance {
      recon = true
    }
  }
}

# --- ENABLE TIME SYNC ---

resource "jamfpro_policy" "enable_time_sync" {
  name                        = "Enable Automatic Time Sync"
  enabled                     = true
  trigger_checkin             = true
  trigger_enrollment_complete = true
  frequency                   = "Once per computer"
  category_id                 = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    scripts {
      id       = jamfpro_script.enable_time_sync.id
      priority = "After"
    }
  }
}

# --- VS CODE PATH POLICY ---
resource "jamfpro_policy" "vscode_path" {
  name            = "Add VS Code to PATH"
  enabled         = true
  trigger_checkin = true
  frequency       = "Once per computer"
  category_id     = jamfpro_category.terraform_managed.id

  scope {
    all_computers      = false
    computer_ids       = []
    computer_group_ids = [jamfpro_smart_computer_group.vscode_installed.id]
  }

  payloads {
    scripts {
      id       = jamfpro_script.vscode_path.id
      priority = "After"
    }
  }

  self_service {
    use_for_self_service = false
  }
}

# --- WALLPAPER DEPLOYMENT POLICY ---

resource "jamfpro_policy" "deploy_wallpaper" {
  name                        = "Deploy Example Wallpaper"
  enabled                     = true
  trigger_checkin             = true
  trigger_login               = true
  trigger_enrollment_complete = true
  frequency                   = "Once per computer"
  category_id                 = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    packages {
      distribution_point = "default"
      package {
        id     = 5 # Example-Wallpaper.pkg
        action = "Install"
      }
    }
    scripts {
      id       = jamfpro_script.set_wallpaper.id
      priority = "After"
    }
  }
}

# --- XCODE ---

resource "jamfpro_policy" "install_xcode_cli_tools" {
  name                        = "Install xcode CLI tools"
  enabled                     = true
  trigger_checkin             = true
  trigger_enrollment_complete = true
  frequency                   = "Once per computer"
  retry_event                 = "check-in"
  retry_attempts              = 3
  category_id                 = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    scripts {
      id       = jamfpro_script.install_xcode_cli_tools.id
      priority = "After"
    }
  }

  self_service {
    use_for_self_service            = false
    feature_on_main_page            = false
    force_users_to_view_description = false
    notification                    = false
    notification_type               = "Self Service"
    notification_subject            = "Install xcode CLI tools"
    install_button_text             = "Install"
    reinstall_button_text           = "Reinstall"
    self_service_icon_id            = 0
  }
}

# --- ADD TO DEVELOPER GROUP ---
resource "jamfpro_policy" "self_service_add_to_developer_group" {
  name        = "Enable Developer Tools Access"
  enabled     = true
  frequency   = "Ongoing"
  category_id = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    scripts {
      id       = jamfpro_script.add_to_developer_group.id
      priority = "After"
    }
  }

  self_service {
    use_for_self_service            = true
    feature_on_main_page            = false
    force_users_to_view_description = false
    self_service_display_name       = "Enable Developer Tools Access"
    self_service_description        = "Grants your account permission to use developer tools (debuggers, profilers). Run this if you see a 'Developer Tools Access' prompt when debugging."
    install_button_text             = "Enable"
    reinstall_button_text           = "Enable"
  }
}

# --- SELF SERVICE: RESET LOOM TCC ---
resource "jamfpro_policy" "self_service_reset_loom_tcc" {
  name        = "Reset Loom Accessibility Permission"
  enabled     = true
  frequency   = "Ongoing"
  category_id = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    scripts {
      id       = jamfpro_script.reset_loom_tcc.id
      priority = "After"
    }
  }

  self_service {
    use_for_self_service            = true
    feature_on_main_page            = false
    force_users_to_view_description = false
    self_service_display_name       = "Reset Loom Accessibility Permission"
    self_service_description        = "Resets Loom's Accessibility permission so it can be re-applied by your device profile. Run this if Loom is showing a permission error, then quit and relaunch Loom."
    install_button_text             = "Reset"
    reinstall_button_text           = "Reset"
  }
}

# --- SPLUNK MCP SERVER CONFIG ---
# Ongoing + check-in so a Mac picks the config up whenever Claude Code appears or
# the token is rotated: the script rewrites the entry whenever it differs and
# exits without writing when it matches. No recon payload — see the note on
# FIELD_INVENTORY_DANGER above.
resource "jamfpro_policy" "configure_splunk_mcp" {
  name            = "Splunk MCP - Configure for Claude Code"
  enabled         = true
  trigger_checkin = true
  frequency       = "Ongoing"
  category_id     = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    scripts {
      id         = jamfpro_script.configure_splunk_mcp.id
      priority   = "After"
      parameter4 = var.splunk_mcp_endpoint
      parameter5 = var.splunk_mcp_token
    }
  }
}

# --- TENABLE NESSUS AGENT REMOVAL (DECOMMISSION IN-479 / IN-484) ---
# Runs the Nessus Agent uninstaller on machines the "Nessus - Installed" smart
# group reports still have it. Ongoing + recurring check-in so it retries every
# check-in until the agent is gone; the uninstaller is idempotent and a safe
# no-op anywhere else. Recon runs after removal so the "Nessus Agent Status" EA
# re-evaluates and the machine drops out of scope as the agent is removed. This
# is additive: the Nessus Agent was deployed outside Terraform, so this policy
# stands up the uninstaller as a managed resource (Jira IN-479 / IN-484).
resource "jamfpro_policy" "remove_nessus_agent" {
  name            = "Nessus Agent - Remove"
  enabled         = true
  trigger_checkin = true
  frequency       = "Ongoing"
  category_id     = jamfpro_category.terraform_managed.id

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.nessus_installed.id]
  }

  payloads {
    scripts {
      id       = jamfpro_script.remove_nessus_agent.id
      priority = "After"
    }
    maintenance {
      recon = true
    }
  }
}
