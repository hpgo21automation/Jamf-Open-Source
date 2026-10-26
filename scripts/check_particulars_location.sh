#!/bin/bash

###############################################################################
# Check if Particulars has Location Services permission
# If not, prompt user to enable it
###############################################################################

currentUser=$(/usr/bin/stat -f "%Su" /dev/console)

if [ "$currentUser" = "root" ] || [ -z "$currentUser" ]; then
    echo "No user logged in"
    exit 0
fi

# Quit Particulars if running so TCC shows current state
/usr/bin/sudo -u "$currentUser" /usr/bin/osascript -e 'tell application "Particulars" to quit' 2>/dev/null

# Check the TCC database for Particulars location permission
tccCheck=$(/usr/bin/sqlite3 "/Users/$currentUser/Library/Application Support/com.apple.TCC/TCC.db" \
    "SELECT auth_value FROM access WHERE client='net.glencode.Particulars' AND service='kTCCServiceLocationServicesAuthorizationStatus';" 2>/dev/null)

# Alternative: Check system TCC database
if [ -z "$tccCheck" ]; then
    tccCheck=$(/usr/bin/sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
        "SELECT auth_value FROM access WHERE client='net.glencode.Particulars' AND service='kTCCServiceLocationServicesAuthorizationStatus';" 2>/dev/null)
fi

# If authorized (value 2 or 3), exit
if [ "$tccCheck" = "2" ] || [ "$tccCheck" = "3" ]; then
    echo "Particulars already has location permission"
    exit 0
fi

echo "Particulars does not have location permission, prompting user..."

# Open System Settings to Location Services and prompt user
/usr/bin/sudo -u "$currentUser" /usr/bin/osascript <<'EOF'
do shell script "open 'x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices'"

delay 1

display dialog "Example IT Request:

Please enable Location Services for Particulars to display your Wi-Fi network name.

1. Find 'Particulars' in the list
2. Toggle the switch to ON

This helps IT identify which network you're connected to." buttons {"I'll Do It Later", "OK"} default button "OK" with title "Enable Location Services" with icon caution
EOF

exit 0