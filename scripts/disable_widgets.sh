#!/bin/bash

###############################################################################
# Disable Desktop Widgets for all users
###############################################################################

currentUser=$(/usr/bin/stat -f "%Su" /dev/console)

if [ "$currentUser" = "root" ] || [ -z "$currentUser" ]; then
    exit 0
fi

# Disable widgets on desktop
sudo -u "$currentUser" defaults write com.apple.WindowManager StandardHideWidgets -bool true
sudo -u "$currentUser" defaults write com.apple.WindowManager StageManagerHideWidgets -bool true

# Restart Dock to apply
killall Dock

echo "Widgets disabled for $currentUser"
exit 0