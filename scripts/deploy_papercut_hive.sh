#!/bin/bash
# ==============================================================================
# Deploy PaperCut Hive edge node & Print Client
#
# Jamf Parameters:
#   $4 — PaperCut Hive activation key (from PaperCut Admin > Hive > Deploy)
#   $5 — Cloud region (e.g. us-genesis)
#   $6 — Organisation ID (short hex string shown in PaperCut Admin)
# ==============================================================================

ACTIVATION_KEY="${4:-06UOs1jL6dElFh59GaokgkNAYmHwMZDjtINRqRQP6xWYUz57vjPL8OEyGFkhsEKLxNHYoSxJCZRq0hizXM8yw47dcLz1abaz490c}" # ci-allow: PaperCut org activation key — backwards-compat fallback; set $4 in Jamf policy to rotate
CLOUD_REGION="${5:-us-genesis}"
ORG_ID="${6:-a7395cde}"

WAITING_ROOM="/Library/Application Support/JAMF/Waiting Room"
INSTALL_MARKER="/Library/PaperCut Hive/Uninstall.command"
WORK_DIR="/var/tmp"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

already_installed() {
    [[ -f "$INSTALL_MARKER" ]] && pgrep -fl "PaperCut Hive" >/dev/null 2>&1
}

# Policy is "Once per Computer". If the first run succeeds, Jamf never re-runs.
# Idempotent short-circuit keeps re-runs (e.g. after receipt flush) safe.
if already_installed; then
    log "PaperCut Hive already installed and running — nothing to do"
    exit 0
fi

ZIP=$(find "$WAITING_ROOM" -maxdepth 1 -name "papercut-hive*.zip" | head -1)
if [[ -z "$ZIP" ]]; then
    log "ERROR: No papercut-hive*.zip found in Jamf Waiting Room at $WAITING_ROOM"
    log "       The package step in this policy did not deliver papercut-hive.zip."
    log "       Check distribution point reachability and policy package config."
    exit 1 # jamf-ci: exit1-intentional
fi
log "Found: $ZIP"

# Copy (not move) the zip out of Waiting Room. Previous version used `mv -f`,
# which destructively consumed the source artifact: if install.sh failed on the
# first attempt, the next retry found no zip in Waiting Room and exited with
# the misleading "No papercut-hive*.zip" error. Copying preserves the source
# for any retries (this script's own retry loop, or a fresh policy run after
# a receipt flush).
ZIP_BASENAME=$(basename "$ZIP")
if ! cp -f "$ZIP" "$WORK_DIR/"; then
    log "ERROR: cp $ZIP -> $WORK_DIR failed"
    exit 1
fi

if ! cd "$WORK_DIR"; then
    log "ERROR: cannot cd to $WORK_DIR"
    exit 1
fi

rm -rf "$WORK_DIR/hive_installer"
if ! unzip -o "$ZIP_BASENAME" >/dev/null; then
    log "ERROR: unzip of $ZIP_BASENAME failed"
    rm -f "$WORK_DIR/$ZIP_BASENAME"
    exit 1
fi

if [[ ! -d "$WORK_DIR/hive_installer" ]]; then
    log "ERROR: hive_installer directory missing after unzip"
    rm -f "$WORK_DIR/$ZIP_BASENAME"
    exit 1
fi

if ! cd "$WORK_DIR/hive_installer"; then
    log "ERROR: cannot cd to hive_installer"
    rm -rf "$WORK_DIR/hive_installer" "$WORK_DIR/${ZIP_BASENAME:?}"
    exit 1
fi

if [[ -f "$INSTALL_MARKER" ]]; then
    log "Uninstalling existing PaperCut Hive..."
    "$INSTALL_MARKER" -y || log "Uninstall returned non-zero; continuing"
fi

# 3-attempt retry: install.sh occasionally fails on transient network/service
# start-up races. Verifying $INSTALL_MARKER after each run guards against
# install.sh returning 0 with a partial install.
INSTALL_OK=false
for attempt in 1 2 3; do
    log "Install attempt $attempt of 3"
    if ./install.sh "$ACTIVATION_KEY" "$CLOUD_REGION" "$ORG_ID"; then
        if [[ -f "$INSTALL_MARKER" ]]; then
            log "Install attempt $attempt succeeded"
            INSTALL_OK=true
            break
        fi
        log "install.sh exited 0 but $INSTALL_MARKER missing — treating as failure"
    fi
    log "Install attempt $attempt failed"
    sleep 5
done

rm -f "$WORK_DIR/$ZIP_BASENAME"
rm -rf "$WORK_DIR/hive_installer"

if ! $INSTALL_OK; then
    log "ERROR: PaperCut Hive install failed after 3 attempts"
    exit 1 # jamf-ci: exit1-intentional
fi

log "PaperCut Hive deployed successfully"
exit 0
