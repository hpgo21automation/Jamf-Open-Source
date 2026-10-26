#!/bin/bash
# ea_crowdstrike_status.sh
# Extension Attribute: reports CrowdStrike Falcon sensor state.
#
# Returns:
#   Not Installed — Falcon.app absent
#   Not Running   — falconctl present but sensor not operational
#   Wrong CID     — sensor running but registered to wrong tenant
#   Running       — sensor running and registered to correct tenant
#
# expected_cid is injected by Terraform templatefile() at deploy time.
# shellcheck disable=SC2154

FALCONCTL="/Applications/Falcon.app/Contents/Resources/falconctl"
EXPECTED_BASE=$(echo "${expected_cid}" | tr '[:lower:]' '[:upper:]' | cut -d- -f1)

if [ ! -d "/Applications/Falcon.app" ] || [ ! -f "$FALCONCTL" ]; then
    echo "<result>Not Installed</result>"
    exit 0
fi

status=$("$FALCONCTL" stats agent_info 2>&1)

if echo "$status" | grep -qE "Sensor operational: true|State: connected"; then
    CURRENT_CID=$("$FALCONCTL" stats 2>&1 | grep -i "cid" | awk '{print $NF}' | head -1)
    CURRENT_BASE=$(echo "$CURRENT_CID" | tr '[:lower:]' '[:upper:]' | cut -d- -f1)
    if [ -n "$CURRENT_BASE" ] && [ "$CURRENT_BASE" != "$EXPECTED_BASE" ]; then
        echo "<result>Wrong CID</result>"
    else
        echo "<result>Running</result>"
    fi
elif [[ "$status" == *"Error"* ]] || [[ "$status" == *"unknown"* ]]; then
    echo "<result>Not Running</result>"
else
    echo "<result>Unknown</result>"
fi
