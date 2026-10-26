#!/bin/bash

set -euo pipefail

DUO_DIR="/Library/Application Support/Duo/Duo Device Health"
PKG_URL="https://dl.duosecurity.com/DuoDesktop-latest.pkg"
TMP_PKG="/tmp/DuoDesktop-latest.pkg"

# Let Duo manage its own certificate (required on macOS 11+)
mkdir -p "$DUO_DIR"
touch "$DUO_DIR/DisableMacOS11CertManagement"

# Suppress auto-launch after install (avoids interrupting the user mid-policy)
touch "$DUO_DIR/NoAutoLaunchAfterInstall"

echo "Downloading Duo Desktop..."
curl -fsSL "$PKG_URL" -o "$TMP_PKG"

echo "Installing Duo Desktop..."
installer -pkg "$TMP_PKG" -target /
rm -f "$TMP_PKG"

echo "Duo Desktop installed successfully."
