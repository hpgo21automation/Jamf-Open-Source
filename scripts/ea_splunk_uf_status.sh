#!/bin/bash
# Reports the last Splunk UF install/upgrade outcome from the status file written
# by install_splunk_uf.sh. Gives the daily compliance check a real root cause
# from inventory, and drives the "Splunk UF - Needs Remediation" smart group
# (matches "FAIL%") so an Ongoing remediation policy re-runs failed installs.
# Status file format: STATE|timestamp|reason
STATUS_FILE="/Library/Application Support/Example/jamf-status/splunk-uf.status"
if [ ! -f "$STATUS_FILE" ]; then
    echo "<result>No Data</result>"
    exit 0
fi
IFS='|' read -r state _ reason < "$STATUS_FILE"
if [ "$state" = "OK" ]; then
    echo "<result>OK</result>"
else
    echo "<result>FAIL: ${reason:-unknown}</result>"
fi
