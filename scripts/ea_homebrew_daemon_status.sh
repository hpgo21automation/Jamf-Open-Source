#!/bin/bash
# Extension Attribute: Homebrew Monitor Daemon Status

LABEL="com.example.blockhomebrew"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"

if [[ ! -f "$PLIST" ]]; then
    echo "<result>Not Installed</result>"
    exit 0
fi

# Single launchctl invocation; awk extracts PID from the matching row
pid=$(launchctl list 2>/dev/null | awk -v label="$LABEL" '$3 == label {print $1; exit}')

if [[ -z "$pid" ]]; then
    echo "<result>Not Running</result>"
elif [[ "$pid" == "-" ]]; then
    echo "<result>Loaded but not running</result>"
else
    echo "<result>Running (PID: $pid)</result>"
fi