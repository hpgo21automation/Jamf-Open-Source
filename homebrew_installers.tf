# --- HOMEBREW PACKAGE INSTALLERS ---

# Self Service icon per Homebrew package. jamfpro_icon downloads the PNG from
# its web source (icon_url in homebrew.auto.tfvars) and uploads it to Jamf Pro,
# returning an icon id the policy references via self_service_icon_id.
resource "jamfpro_icon" "homebrew" {
  for_each = { for k, v in var.homebrew_packages : k => v if v.icon_url != "" }

  icon_file_web_source = each.value.icon_url
}

resource "jamfpro_policy" "homebrew_packages" {
  for_each = var.homebrew_packages

  name        = "Install ${each.value.display_name}"
  enabled     = each.value.enabled
  frequency   = "Ongoing"
  category_id = jamfpro_category.terraform_managed.id

  scope {
    all_computers = true
  }

  payloads {
    scripts {
      id         = jamfpro_script.homebrew_installer.id
      priority   = "After"
      parameter4 = each.value.formula
      parameter5 = each.value.tap
      parameter6 = each.value.cask ? "cask" : "formula"
    }
  }

  self_service {
    use_for_self_service      = true
    feature_on_main_page      = false
    self_service_display_name = each.value.display_name
    self_service_description  = "Installs ${each.value.display_name}"
    install_button_text       = "Install"
    reinstall_button_text     = "Reinstall"
    self_service_icon_id      = try(jamfpro_icon.homebrew[each.key].id, 0)
  }
}

# --- HOMEBREW PACKAGE INSTALL REMEDIATION POLICY ---
# The Self Service policies above only run when a human clicks Install, so a
# device whose install fails stays failing until someone manually retries it
# — contradicting the "Homebrew Install - Failing" smart group's own comment
# (smart_groups.tf) that "the Ongoing install policies retry every check-in".
# This single Ongoing policy is scoped to that smart group and reruns
# homebrew_installer.sh (with the same per-package parameters) every
# check-in for any device currently in the group; the EA re-evaluates via
# the recon below and the device leaves once its packages install OK.
resource "jamfpro_policy" "remediate_homebrew_packages" {
  for_each = var.homebrew_packages

  name            = "Remediate ${each.value.display_name} Install"
  enabled         = each.value.enabled
  trigger_checkin = true
  frequency       = "Ongoing"
  category_id     = jamfpro_category.terraform_managed.id

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.homebrew_install_failing.id]
  }

  payloads {
    scripts {
      id         = jamfpro_script.homebrew_installer.id
      priority   = "After"
      parameter4 = each.value.formula
      parameter5 = each.value.tap
      parameter6 = each.value.cask ? "cask" : "formula"
    }
    maintenance {
      recon = true
    }
  }
}
