#!/bin/bash

###############################################################################
# Example Desktop & Lock Screen Wallpaper Deployment Script
# Sets corporate wallpaper for current user's desktop and lock screen
#
# FIX: Script was immediately exiting 1 if wallpaper asset was missing.
#      This caused false failures when the Example branding package was
#      still deploying concurrently (race condition at enrollment time).
#      Added a 30-second retry loop before giving up, plus diagnostic output
#      to make future triage easier.
#
# FIX 2: Increased retry window from 30s to 120s. On devices with slower
#         package delivery or during high-concurrency enrollment batches the
#         branding package can take well over 30s to land, triggering a
#         spurious failure even though the asset eventually arrives.
###############################################################################

WALLPAPER_PATH="/Library/Application Support/Example/Branding/Example-Wallpaper.png"

# Retry loop: wait up to 120s for the branding package to finish deploying
MAX_WAIT=120
WAITED=0
while [ ! -f "$WALLPAPER_PATH" ] && [ "$WAITED" -lt "$MAX_WAIT" ]; do
    echo "Waiting for wallpaper asset (${WAITED}s elapsed)..."
    sleep 5
    WAITED=$((WAITED + 5))
done

# Verify wallpaper exists after retry window
if [ ! -f "$WALLPAPER_PATH" ]; then
    echo "ERROR: Wallpaper not found at $WALLPAPER_PATH after ${MAX_WAIT}s"
    echo "Diagnostics:"
    BRANDING_DIR="/Library/Application Support/Example/Branding"
    if [ -d "$BRANDING_DIR" ]; then
        echo "  Branding dir exists. Contents:"
        ls -la "$BRANDING_DIR"
    else
        echo "  Branding dir does NOT exist: $BRANDING_DIR"
        echo "  Parent dir contents:"
        ls -la "/Library/Application Support/Example/" 2>/dev/null || \
            echo "  /Library/Application Support/Example/ not found"
    fi
    echo "Ensure the Example-Wallpaper package is installed before this policy runs."
    exit 1 # jamf-ci: exit1-intentional
fi

# Get current logged-in user
currentUser=$(/usr/bin/stat -f "%Su" /dev/console)

if [ "$currentUser" = "root" ] || [ -z "$currentUser" ]; then
    echo "No user logged in, skipping wallpaper set"
    exit 0
fi

currentUserID=$(/usr/bin/id -u "$currentUser")
echo "Setting wallpaper for user: $currentUser (UID: $currentUserID)"

###############################################################################
# Set Desktop Wallpaper
###############################################################################

# Method 1: Use desktoppr if available
if [ -f "/usr/local/bin/desktoppr" ]; then
    /usr/bin/sudo -u "$currentUser" /usr/local/bin/desktoppr "$WALLPAPER_PATH"
    echo "Desktop wallpaper set via desktoppr"
else
    # Method 2: Use osascript via launchctl
    /bin/launchctl asuser "$currentUserID" /usr/bin/osascript -e "
    tell application \"System Events\"
        tell every desktop
            set picture to \"$WALLPAPER_PATH\"
        end tell
    end tell
    " 2>/dev/null

    if [ $? -eq 0 ]; then
        echo "Desktop wallpaper set via osascript"
    else
        # Method 3: Direct osascript as user (fallback)
        /usr/bin/sudo -u "$currentUser" /usr/bin/osascript -e "
        tell application \"System Events\"
            tell every desktop
                set picture to \"$WALLPAPER_PATH\"
            end tell
        end tell
        "
        echo "Desktop wallpaper set via osascript fallback"
    fi
fi

###############################################################################
# Set Lock Screen Wallpaper (macOS 14+)
###############################################################################

echo "Setting lock screen wallpaper..."

# Get user's GeneratedUID
userUUID=$(dscl . -read /Users/"$currentUser" GeneratedUID 2>/dev/null | awk '{print $2}')

if [ -n "$userUUID" ]; then
    LOCK_SCREEN_DIR="/Library/Caches/Desktop Pictures/$userUUID"
    
    # Create directory if it doesn't exist
    mkdir -p "$LOCK_SCREEN_DIR"
    
    # Copy wallpaper as lockscreen.png
    cp "$WALLPAPER_PATH" "$LOCK_SCREEN_DIR/lockscreen.png"
    
    # Set proper permissions
    chmod 644 "$LOCK_SCREEN_DIR/lockscreen.png"
    chown "$currentUser:staff" "$LOCK_SCREEN_DIR/lockscreen.png"
    
    echo "Lock screen wallpaper set at: $LOCK_SCREEN_DIR/lockscreen.png"
else
    echo "WARNING: Could not determine user UUID, lock screen not set"
fi

# Also set for any existing Desktop Pictures cache folders
CACHE_DIR="/Library/Caches/Desktop Pictures"
if [ -d "$CACHE_DIR" ]; then
    for folder in "$CACHE_DIR"/*/; do
        if [ -d "$folder" ]; then
            cp "$WALLPAPER_PATH" "${folder}lockscreen.png" 2>/dev/null
            chmod 644 "${folder}lockscreen.png" 2>/dev/null
        fi
    done
    echo "Updated all existing lock screen cache folders"
fi

echo "Wallpaper deployment complete"
exit 0
