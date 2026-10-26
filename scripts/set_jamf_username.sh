#!/bin/bash

# Set Jamf Pro's "End Username" field to the Jamf Connect DisplayName for the
# currently logged-in console user. Triggered on every login so the device
# record stays in sync if the user changes.

currentUser=$(ls -l /dev/console | awk '/ / { print $3 }')
jamfConnectStateLocation="/Users/${currentUser}/Library/Preferences/com.jamf.connect.state.plist"

displayName=$(/usr/libexec/PlistBuddy -c "Print :DisplayName" "$jamfConnectStateLocation" 2>/dev/null)

if [ -z "$displayName" ]; then
    echo "Error: Jamf Connect DisplayName missing or blank for $currentUser (plist: $jamfConnectStateLocation)."
    exit 1
fi

/usr/local/jamf/bin/jamf recon -endUsername "$displayName"
echo "Successfully updated Jamf Pro Username to $displayName."
exit 0
