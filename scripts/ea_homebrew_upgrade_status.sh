#!/bin/bash
# Reports the last Homebrew weekly-upgrade outcome from the status file written
# by upgrade_homebrew_packages.sh. Gives the daily compliance check a real root
# cause from inventory instead of only Jamf's Failed flag, and drives the
# "Homebrew Upgrade - Failing" smart group (matches "FAIL%").
# Status file format: STATE|timestamp|reason
STATUS_FILE="/Library/Application Support/Example/jamf-status/homebrew-upgrade.status"
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
