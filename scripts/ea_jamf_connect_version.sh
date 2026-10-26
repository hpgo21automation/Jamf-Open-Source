#!/bin/sh
# Reports the installed Jamf Connect *login window* plugin version, or
# "Not Installed" / "Unknown".
#
# This is deliberately the login plugin and not the Jamf Connect app: the plugin
# ships in the static JamfConnectLogin.pkg and does NOT auto-update, whereas the
# app tracks the Jamf App Catalog. The two drift apart, and it is the plugin
# version that determines whether SharedTokenTrustedApplications is honoured —
# i.e. whether Self Service+ stops prompting for the login keychain password.
PLUGIN="/Library/Security/SecurityAgentPlugins/JamfConnectLogin.bundle"

if [ -d "$PLUGIN" ]; then
    version=$(defaults read "$PLUGIN/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)
    echo "<result>${version:-Unknown}</result>"
else
    echo "<result>Not Installed</result>"
fi
