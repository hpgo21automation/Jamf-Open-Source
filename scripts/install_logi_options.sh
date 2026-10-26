#!/bin/bash
# ==============================================================================
# Logitech Options+ Installer for Jamf Pro
# ==============================================================================
# Homebrew can't deliver this app: the `logi-options+` cask runs the vendor
# installer via `sudo` interactively (the cask marks the install step
# `sudo: True`), which fails under the non-root srv_mac brew pipeline with
# "sudo: a terminal is required to read the password". Jamf runs policy scripts
# as root, so we drive the same vendor installer directly — no sudo prompt —
# using its documented --quiet (silent) flag.
#
# Source: Logitech's official "latest" installer (the same URL Homebrew uses).
# A reboot is recommended for the install to fully take effect.
# ==============================================================================

set -uo pipefail

ZIP_URL="https://download01.logi.com/web/ftp/pub/techsupport/optionsplus/logioptionsplus_installer.zip"
APP="/Applications/logioptionsplus.app"
LOG="/var/log/example_logi_options_install.log"
WORK="$(mktemp -d /tmp/logioptions.XXXXXX)"
# Pre-#115 Homebrew install path wrote a FAIL marker here. The vendor installer
# below never touches it, so we have to clear it explicitly or the device stays
# stuck in the "Homebrew Install - Failing" smart group.
STALE_BREW_STATUS="/Library/Application Support/Example/jamf-status/homebrew-install-logi-options+.status"

# log() tees to stdout so the message also lands in the Jamf policy result.
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG"; }
trap 'rm -rf "$WORK"' EXIT

echo "============================================" >> "$LOG"
log "Logi Options+ install"

# Idempotent cleanup of the pre-#115 Homebrew status marker. Runs before the
# "already installed" short-circuit so machines that successfully migrated to
# the vendor installer still clear the stale FAIL the next time the policy fires.
if [ -e "$STALE_BREW_STATUS" ]; then
    if rm -f "$STALE_BREW_STATUS" 2>>"$LOG"; then
        log "Removed stale Homebrew status marker: $STALE_BREW_STATUS"
    else
        log "WARN: failed to remove stale Homebrew status marker: $STALE_BREW_STATUS"
    fi
fi

# Already installed — Logi Options+ self-updates via its own updater, so a
# skip-if-present check keeps recurring runs idempotent. (A Self Service
# reinstall on a fresh machine still installs.)
if [ -d "$APP" ]; then
    log "Already installed at $APP — nothing to do"
    exit 0
fi

ZIP="$WORK/logioptionsplus_installer.zip"
log "Downloading installer..."
attempt=0
until [ "$attempt" -ge 3 ]; do
    attempt=$((attempt + 1))
    if curl -fsSL --max-time 300 -o "$ZIP" "$ZIP_URL"; then
        break
    fi
    log "Download attempt $attempt failed; retrying..."
    sleep 5
done
if [ ! -s "$ZIP" ]; then
    log "ERROR: download failed after 3 attempts"
    exit 1
fi

log "Expanding archive..."
if ! ditto -x -k "$ZIP" "$WORK" >> "$LOG" 2>&1; then
    log "ERROR: failed to expand installer archive"
    exit 1
fi

INSTALLER_APP=$(/usr/bin/find "$WORK" -maxdepth 2 -name "logioptionsplus_installer.app" -type d | head -1)
if [ -z "$INSTALLER_APP" ]; then
    log "ERROR: logioptionsplus_installer.app not found in archive"
    exit 1
fi

# Defense in depth: verify the downloaded installer is intact and signed by
# Logitech before executing it as root.
if ! codesign --verify --deep --strict "$INSTALLER_APP" >> "$LOG" 2>&1; then
    log "ERROR: installer code signature failed verification — aborting"
    exit 1
fi
AUTHORITY=$(codesign -dvv "$INSTALLER_APP" 2>&1 | grep -i "^Authority=" | head -1)
if ! echo "$AUTHORITY" | grep -qi "Logitech"; then
    log "ERROR: installer not signed by Logitech (got: ${AUTHORITY:-none}) — aborting"
    exit 1
fi
log "Signature OK: $AUTHORITY"

log "Running silent install..."
# Running as root (Jamf), so the installer's privileged steps succeed without
# the interactive sudo prompt that breaks the Homebrew cask path.
"$INSTALLER_APP/Contents/MacOS/logioptionsplus_installer" --quiet >> "$LOG" 2>&1 || \
    log "Installer returned non-zero (verifying result anyway)"

# Verify by presence of the installed app.
sleep 5
if [ -d "$APP" ]; then
    log "SUCCESS: Logi Options+ installed at $APP"
    log "NOTE: a reboot is recommended for full functionality"
    exit 0
fi

log "ERROR: install verification failed — $APP not present"
exit 1 # jamf-ci: exit1-intentional
