#!/bin/bash

###############################################################################
# Splunk Universal Forwarder - Configure Inputs for Example
# 
# This script configures log inputs. Can be re-run to update configuration.
# Only restarts Splunk if configuration has changed.
#
# Version is injected by Terraform - DO NOT EDIT IN JAMF
# Version: ${script_version}
#
# Indexes required in Splunk Cloud:
#   - macevents (system and auth logs)
#   - macsecurity (audit logs, crash reports)
#   - jamf-endpoints (Jamf Pro, Setup Manager, Connect)
#
# Splunk Cloud: https://example.splunkcloud.com/
# Trigger update: 2026-01-11
###############################################################################

SPLUNK_HOME="/opt/splunkforwarder"
TA_NAME="example_macos_ta"
TA_PATH="$SPLUNK_HOME/etc/apps/$TA_NAME"
LOG_FILE="/var/log/example_splunk_inputs.log"
PLIST_DOMAIN="com.example.splunk"
# shellcheck disable=SC2154  # injected by Terraform templatefile()
CONFIG_VERSION="${script_version}"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log "=========================================="
log "Splunk Input Configuration v$CONFIG_VERSION"
log "=========================================="

# Check Splunk is installed
if [ ! -f "$SPLUNK_HOME/bin/splunk" ]; then
    log "Splunk UF not installed, skipping"
    exit 0
fi

# Check if already at current version
VERSION_FILE="$TA_PATH/.config_version"
if [ -f "$VERSION_FILE" ]; then
    INSTALLED_VERSION=$(cat "$VERSION_FILE")
    if [ "$INSTALLED_VERSION" == "$CONFIG_VERSION" ]; then
        log "Already at version $CONFIG_VERSION, no changes needed"
        # Still write to plist for EA tracking
        defaults write "/Library/Preferences/$PLIST_DOMAIN" InputsScriptVersion "$CONFIG_VERSION"
        exit 0
    fi
    log "Upgrading from $INSTALLED_VERSION to $CONFIG_VERSION"
else
    log "First time configuration"
fi

# Create TA directory structure
log "Creating $TA_NAME..."
mkdir -p "$TA_PATH/local"
mkdir -p "$TA_PATH/default"
mkdir -p "$TA_PATH/bin"

# app.conf
cat > "$TA_PATH/default/app.conf" << EOF
[install]
is_configured = 1
state = enabled
build = $(date +%Y%m%d%H%M)

[ui]
is_visible = false
label = Example macOS TA

[launcher]
author = Example Security Team
description = macOS and Jamf log inputs for Example
version = $CONFIG_VERSION
EOF

# inputs.conf
log "Writing inputs.conf..."
cat > "$TA_PATH/local/inputs.conf" << 'INPUTSCONF'
# ============================================
# Example macOS Technology Add-on
# Splunk Cloud: example.splunkcloud.com
# ============================================

# --- macOS Install Log ---
[monitor:///var/log/install.log]
disabled = false
index = macevents
sourcetype = macos:install

# --- macOS Unified Log - Authentication ---
# Filtered to security-relevant subsystems only. CloudKit/iCloud noise excluded.
[script://$SPLUNK_HOME/etc/apps/example_macos_ta/bin/collect_auth_logs.sh]
disabled = false
interval = 60
index = macevents
sourcetype = macos:unifiedlog:auth
source = unified_log_auth

# macos:system:syslog disabled - redundant with unified log
# macos:unifiedlog:system disabled - ManagedClient/mdmclient covered by jamf:agent

# --- Setup Manager (Apple) ---
[monitor:///Library/Logs/Setup Manager.log]
disabled = false
index = macevents
sourcetype = macos:setupmanager

# --- Microsoft Apps ---
[monitor:///Library/Logs/Microsoft/*.log]
disabled = false
index = macevents
sourcetype = macos:microsoft

# --- Diagnostic Reports ---
[monitor:///Library/Logs/DiagnosticReports/*.crash]
disabled = false
index = macsecurity
sourcetype = macos:crash

[monitor:///Library/Logs/DiagnosticReports/*.hang]
disabled = false
index = macsecurity
sourcetype = macos:hang

[monitor:///Library/Logs/DiagnosticReports/*.diag]
disabled = false
index = macsecurity
sourcetype = macos:diag

# --- Jamf Pro Agent ---
[monitor:///var/log/jamf.log]
disabled = false
index = jamf-endpoints
sourcetype = jamf:agent

# --- Jamf Setup Manager ---
[monitor:///var/log/jamf-setup-manager.log]
disabled = false
index = jamf-endpoints
sourcetype = jamf:setupmanager

[monitor:///private/var/log/jamf-setup-manager.log]
disabled = false
index = jamf-endpoints
sourcetype = jamf:setupmanager

# --- Jamf Connect ---
[monitor:///Library/Application Support/JamfConnect/Logs/*.log]
disabled = false
index = jamf-endpoints
sourcetype = jamf:connect

# --- Homebrew Package Installs ---
[monitor:///var/log/homebrew_installs.log]
disabled = false
index = jamf-endpoints
sourcetype = jamf:homebrew

# --- OpenBSM Audit Logs ---
[monitor:///var/audit/*]
disabled = false
index = macsecurity
sourcetype = macos:bsm
INPUTSCONF

# Auth log collection script
# Scoped to security-relevant subsystems. CloudKit/iCloud noise filtered out.
cat > "$TA_PATH/bin/collect_auth_logs.sh" << 'SCRIPT'
#!/bin/bash
/usr/bin/log show --style json --predicate '
    (
        subsystem == "com.apple.opendirectoryd" OR
        subsystem == "com.apple.Authorization" OR
        subsystem == "com.apple.securityd" OR
        subsystem == "com.apple.loginwindow" OR
        subsystem == "com.apple.screensharing"
    ) AND NOT eventMessage CONTAINS "CloudKit"
      AND NOT eventMessage CONTAINS "no account"
      AND NOT eventMessage CONTAINS "No account"
' --last 2m 2>/dev/null | /usr/bin/grep -v "^Timestamp"
SCRIPT

chmod +x "$TA_PATH/bin/"*.sh
chown -R root:wheel "$TA_PATH"

# Write version file (for script's own tracking)
echo "$CONFIG_VERSION" > "$VERSION_FILE"

# ============================================
# CRITICAL: Write version to plist for EA/Smart Group tracking
# This is what allows Terraform updates to auto-trigger
# ============================================
defaults write "/Library/Preferences/$PLIST_DOMAIN" InputsScriptVersion "$CONFIG_VERSION"
log "Wrote version $CONFIG_VERSION to $PLIST_DOMAIN plist"

# Restart Splunk to apply changes
log "Restarting Splunk..."
"$SPLUNK_HOME/bin/splunk" restart 2>&1 | tee -a "$LOG_FILE"

# Retry loop — splunkd can take 15-30 s to fully start on slower machines.
# Check up to 10 times with 5-second waits (50 s total) before giving up.
SPLUNK_UP=false
for i in $(seq 1 10); do
    sleep 5
    if pgrep -x "splunkd" > /dev/null; then
        SPLUNK_UP=true
        break
    fi
    log "Waiting for splunkd to start (attempt $i/10)..."
done

if $SPLUNK_UP; then
    log "=========================================="
    log "SUCCESS: Inputs configured v$CONFIG_VERSION"
    log "=========================================="
    exit 0
else
    log "ERROR: Splunk failed to restart after 50 s"
    exit 1
fi
