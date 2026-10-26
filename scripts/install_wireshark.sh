#!/bin/bash

set -euo pipefail

WIRESHARK_APP="/Applications/Wireshark.app"
CURRENT_USER=$(stat -f "%Su" /dev/console)
LOG="/var/log/install_wireshark.log"
CHMODBPF_DIR="/Library/Application Support/Wireshark/ChmodBPF"
CHMODBPF_SCRIPT="$CHMODBPF_DIR/ChmodBPF"
LAUNCHDAEMON_PLIST="/Library/LaunchDaemons/org.wireshark.ChmodBPF.plist"

exec > >(tee -a "$LOG") 2>&1
echo "$(date): Starting Wireshark install/configure"

# Install or upgrade from official DMG — avoids nested sudo issue with Homebrew cask
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    DMG_URL="https://www.wireshark.org/download/osx/Wireshark%20Latest%20Arm%2064.dmg"
else
    DMG_URL="https://www.wireshark.org/download/osx/Wireshark%20Latest%20Intel%2064.dmg"
fi
TMP_DMG="/tmp/Wireshark-latest.dmg"
MOUNT_POINT="/tmp/wireshark-install-mount"

# Check installed version vs latest by comparing bundle version
INSTALLED_VERSION=""
if [[ -d "$WIRESHARK_APP" ]]; then
    INSTALLED_VERSION=$(defaults read "$WIRESHARK_APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)
fi

echo "$(date): Downloading Wireshark DMG (installed: ${INSTALLED_VERSION:-none})..."
curl -fsSL "$DMG_URL" -o "$TMP_DMG"

echo "$(date): Mounting DMG..."
hdiutil attach "$TMP_DMG" -mountpoint "$MOUNT_POINT" -nobrowse -quiet

DMG_VERSION=$(defaults read "$MOUNT_POINT/Wireshark.app/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)
echo "$(date): DMG version: $DMG_VERSION"

if [[ "$INSTALLED_VERSION" == "$DMG_VERSION" ]]; then
    echo "$(date): Wireshark $DMG_VERSION already installed, skipping copy."
else
    echo "$(date): Installing Wireshark $DMG_VERSION..."
    rm -rf "$WIRESHARK_APP"
    cp -R "$MOUNT_POINT/Wireshark.app" /Applications/
    echo "$(date): Wireshark $DMG_VERSION installed."
fi

hdiutil detach "$MOUNT_POINT" -quiet
rm -f "$TMP_DMG"

# Create access_bpf group (GID 173 matches official ChmodBPF.pkg)
if ! dscl . -read /Groups/access_bpf &>/dev/null; then
    echo "$(date): Creating access_bpf group..."
    dscl . -create /Groups/access_bpf
    dscl . -create /Groups/access_bpf PrimaryGroupID 173
fi

# Install ChmodBPF helper and LaunchDaemon
mkdir -p "$CHMODBPF_DIR"
cat > "$CHMODBPF_SCRIPT" << 'EOF'
#!/bin/sh
chgrp access_bpf /dev/bpf*
chmod g+rw /dev/bpf*
EOF
chmod 754 "$CHMODBPF_SCRIPT"

cat > "$LAUNCHDAEMON_PLIST" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>org.wireshark.ChmodBPF</string>
    <key>Program</key>
    <string>/Library/Application Support/Wireshark/ChmodBPF/ChmodBPF</string>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF
chmod 644 "$LAUNCHDAEMON_PLIST"

if launchctl print system/org.wireshark.ChmodBPF &>/dev/null; then
    launchctl bootout system "$LAUNCHDAEMON_PLIST" 2>/dev/null || true
fi
launchctl bootstrap system "$LAUNCHDAEMON_PLIST"
echo "$(date): ChmodBPF LaunchDaemon loaded"

# Add logged-in user to access_bpf group
if [[ -n "$CURRENT_USER" ]] && [[ "$CURRENT_USER" != "root" ]]; then
    if ! dscl . -read /Groups/access_bpf GroupMembership 2>/dev/null | grep -qw "$CURRENT_USER"; then
        dscl . -append /Groups/access_bpf GroupMembership "$CURRENT_USER"
        echo "$(date): Added $CURRENT_USER to access_bpf group"
    else
        echo "$(date): $CURRENT_USER already in access_bpf group"
    fi
fi

echo "$(date): Wireshark setup complete"
exit 0
