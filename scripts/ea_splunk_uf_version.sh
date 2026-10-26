#!/bin/bash
# Reports the installed Splunk Universal Forwarder version (or "Not Installed").
# Drives the "Splunk UF - Needs Upgrade" smart group: a device is in scope when
# this value != the Terraform-pinned splunk_target_version.
VERSION_FILE="/opt/splunkforwarder/etc/splunk.version"
if [ -f "$VERSION_FILE" ]; then
    version=$(grep -E '^VERSION=' "$VERSION_FILE" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    echo "<result>${version:-Unknown}</result>"
else
    echo "<result>Not Installed</result>"
fi
