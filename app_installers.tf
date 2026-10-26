resource "jamfpro_app_installer" "apps" {
  for_each = var.app_catalog_apps

  name                               = each.value.app_title_name
  app_title_name                     = each.value.app_title_name
  enabled                            = each.value.enabled
  deployment_type                    = each.value.deployment_type
  update_behavior                    = "AUTOMATIC"
  category_id                        = jamfpro_category.terraform_managed.id
  site_id                            = -1
  smart_group_id                     = each.value.smart_group_id
  install_predefined_config_profiles = true
  trigger_admin_notifications        = true

  self_service_settings {
    include_in_featured_category   = each.value.deployment_type == "SELF_SERVICE"
    include_in_compliance_category = false
    force_view_description         = false
  }

  notification_settings {
    notification_interval = 0
    deadline              = 0
    quit_delay            = 0
    relaunch              = false
    suppress              = false
  }

  lifecycle {
    ignore_changes = [notification_settings]
  }
}