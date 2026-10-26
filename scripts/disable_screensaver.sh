#!/bin/bash

###############################################################################
# Example Screen Saver - Set to Wallpaper Image
# Configures screen saver to display the corporate wallpaper
###############################################################################

WALLPAPER_PATH="/Library/Application Support/Example/Branding/Example-Wallpaper.png"

currentUser=$(/usr/bin/stat -f "%Su" /dev/console)

if [ "$currentUser" = "root" ] || [ -z "$currentUser" ]; then
    exit 0
fi

USER_HOME="/Users/$currentUser"

# Verify wallpaper exists — exit 0 gracefully if not yet deployed.
# The Deploy Example Wallpaper policy may not have run yet on this device.
# This policy is Ongoing so it will retry on the next check-in once the
# wallpaper package has been installed.
if [ ! -f "$WALLPAPER_PATH" ]; then
    echo "Wallpaper not found at $WALLPAPER_PATH — skipping until wallpaper is deployed"
    exit 0
fi

echo "Configuring screen saver for $currentUser"

# Create screen saver photo folder
SCREENSAVER_PHOTOS="$USER_HOME/Library/Screen Savers/Example"
mkdir -p "$SCREENSAVER_PHOTOS"
cp "$WALLPAPER_PATH" "$SCREENSAVER_PHOTOS/"
chown -R "$currentUser:staff" "$SCREENSAVER_PHOTOS"

# Get hardware UUID for ByHost preferences
hwUUID=$(system_profiler SPHardwareDataType | awk '/UUID/ { print $3 }') # ci-allow: ByHost pref path requires hardware UUID; ioreg alternative untested here

# Method 1: Try using the "Album Artwork" or shifting tiles screen saver with custom folder
# This varies by macOS version

# For macOS Sonoma/Sequoia - use the built-in photo shuffler
sudo -u "$currentUser" defaults -currentHost write com.apple.screensaver moduleDict -dict \
    moduleName -string "AppStorePhotos" \
    path -string "/System/Library/ExtensionKit/Extensions/AppStorePhotos.appex" \
    type -int 0

# Set custom folder path
sudo -u "$currentUser" defaults -currentHost write com.apple.screensaver.AppStorePhotos CustomFolderPath -string "$SCREENSAVER_PHOTOS"
sudo -u "$currentUser" defaults -currentHost write com.apple.screensaver.AppStorePhotos SelectedSource -int 4

# Method 2: Alternative - use Classic screen saver
sudo -u "$currentUser" defaults -currentHost write com.apple.ScreenSaver.iLifeSlideShows styleKey -string "VintagePrints"
sudo -u "$currentUser" defaults -currentHost write com.apple.ScreenSaverPhotoChooser CustomFolderDict -dict \
    identifier -string "$SCREENSAVER_PHOTOS" \
    name -string "Example"
sudo -u "$currentUser" defaults -currentHost write com.apple.ScreenSaverPhotoChooser SelectedFolderPath -string "$SCREENSAVER_PHOTOS"
sudo -u "$currentUser" defaults -currentHost write com.apple.ScreenSaverPhotoChooser SelectedSource -int 4

# Set idle time (300 seconds = 5 minutes)
sudo -u "$currentUser" defaults -currentHost write com.apple.screensaver idleTime -int 300

# Also set via ByHost
sudo -u "$currentUser" defaults write "$USER_HOME/Library/Preferences/ByHost/com.apple.screensaver.$hwUUID" idleTime -int 300

# Restart preference services
killall cfprefsd 2>/dev/null

echo "Screen saver configured for $currentUser"
echo "Photo folder: $SCREENSAVER_PHOTOS"
exit 0