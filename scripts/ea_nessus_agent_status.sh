#!/bin/bash
# ea_nessus_agent_status.sh
# Extension Attribute: reports whether the Tenable Nessus Agent is present.
# Drives the "Nessus - Installed" smart group that scopes the IN-484 removal
# policy (Tenable decommission, Jira IN-479 / IN-484). A machine leaves that
# group once the uninstaller has stripped the agent, so the removal policy
# self-limits.
#
# Returns:
#   Installed     — /Library/NessusAgent exists, or the launch daemon or
#                   loaded launchd service is present
#   Not Installed — none of the above found

AGENT_DIR="/Library/NessusAgent"
LAUNCH_DAEMON="/Library/LaunchDaemons/com.tenablesecurity.nessusagent.plist"
SERVICE_LABEL="com.tenablesecurity.nessusagent"

if [ -d "$AGENT_DIR" ] || [ -f "$LAUNCH_DAEMON" ] || /bin/launchctl list 2>/dev/null | grep -q "$SERVICE_LABEL"; then
    echo "<result>Installed</result>"
else
    echo "<result>Not Installed</result>"
fi
