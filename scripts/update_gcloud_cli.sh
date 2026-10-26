#!/bin/bash
# Update Google Cloud CLI to latest version
# Runs as the console user so gcloud components update has write permission.

CONSOLE_USER=$(stat -f "%Su" /dev/console)
if [[ -z "$CONSOLE_USER" || "$CONSOLE_USER" == "root" ]]; then
    echo "No user logged in, skipping gcloud update"
    exit 0
fi

USER_HOME=$(dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')

# Find gcloud — check common install locations
GCLOUD_BIN=""
for candidate in \
    "/usr/local/google-cloud-sdk/bin/gcloud" \
    "/opt/homebrew_srv/bin/gcloud" \
    "/opt/homebrew/bin/gcloud" \
    "$USER_HOME/google-cloud-sdk/bin/gcloud"; do
    if [[ -x "$candidate" ]]; then
        GCLOUD_BIN="$candidate"
        break
    fi
done

if [[ -z "$GCLOUD_BIN" ]]; then
    echo "gcloud not installed, skipping update"
    exit 0
fi

SDK_DIR=$(dirname "$(dirname "$GCLOUD_BIN")")
echo "Found gcloud at: $GCLOUD_BIN (SDK: $SDK_DIR)"

CURRENT_VERSION=$(sudo -u "$CONSOLE_USER" "$GCLOUD_BIN" version 2>/dev/null | head -n 1)
echo "Current version: $CURRENT_VERSION"

# Run update as the console user — components update needs write access to the SDK dir
echo "Checking for updates..."
if sudo -u "$CONSOLE_USER" \
    HOME="$USER_HOME" \
    "$GCLOUD_BIN" components update --quiet 2>&1; then
    UPDATED_VERSION=$(sudo -u "$CONSOLE_USER" "$GCLOUD_BIN" version 2>/dev/null | head -n 1)
    echo "Version after update: $UPDATED_VERSION"
else
    echo "WARNING: gcloud components update returned non-zero — may already be up to date or Homebrew-managed"
fi

exit 0
