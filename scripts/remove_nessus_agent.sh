#!/bin/bash
#
# remove_nessus_agent.sh
# Uninstalls the Tenable Nessus Agent from a macOS host (Tenable decommission,
# Jira IN-479 / IN-484). Runs as a Jamf policy script (root). Idempotent:
# exits 0 whether or not the agent is present. Jamf passes $1=mount,$2=host,
# $3=user (unused).
#
set -u

LOG="/var/log/nessus_agent_removal.log"
AGENT_DIR="/Library/NessusAgent"
NESSUSCLI="${AGENT_DIR}/run/sbin/nessuscli"
LAUNCH_DAEMON="/Library/LaunchDaemons/com.tenablesecurity.nessusagent.plist"
SERVICE_LABEL="com.tenablesecurity.nessusagent"
PREF_PANE="/Library/PreferencePanes/Nessus Agent Preferences.prefPane"

log() {
    printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$LOG"
}

log "=== Nessus Agent removal started (IN-484) ==="

if [ ! -d "$AGENT_DIR" ] && [ ! -f "$LAUNCH_DAEMON" ] && ! /bin/launchctl list 2>/dev/null | grep -q "$SERVICE_LABEL"; then
    log "No Nessus Agent components found. Nothing to remove."
    exit 0
fi

if [ -x "$NESSUSCLI" ]; then
    log "Unlinking agent from manager..."
    "$NESSUSCLI" agent unlink >>"$LOG" 2>&1 && log "Unlink OK" || log "Unlink non-zero (already unlinked/unreachable) - continuing"
else
    log "nessuscli not found - skipping unlink"
fi

if /bin/launchctl list 2>/dev/null | grep -q "$SERVICE_LABEL"; then
    /bin/launchctl remove "$SERVICE_LABEL" 2>>"$LOG" || log "launchctl remove non-zero - continuing"
fi
if [ -f "$LAUNCH_DAEMON" ]; then
    /bin/launchctl bootout system "$LAUNCH_DAEMON" 2>/dev/null || true
    rm -f "$LAUNCH_DAEMON" && log "Removed $LAUNCH_DAEMON"
fi

if [ -d "$AGENT_DIR" ]; then
    rm -rf "$AGENT_DIR" && log "Removed $AGENT_DIR"
fi
if [ -d "$PREF_PANE" ]; then
    rm -rf "$PREF_PANE" && log "Removed preference pane"
fi

while IFS= read -r pkg; do
    [ -n "$pkg" ] || continue
    /usr/sbin/pkgutil --forget "$pkg" >>"$LOG" 2>&1 && log "Forgot receipt $pkg"
done < <(/usr/sbin/pkgutil --pkgs 2>/dev/null | grep -i -E 'tenable|nessus')

if [ ! -d "$AGENT_DIR" ] && [ ! -f "$LAUNCH_DAEMON" ] && ! /bin/launchctl list 2>/dev/null | grep -q "$SERVICE_LABEL"; then
    log "Verification passed: no Nessus Agent components remain."
    exit 0
else
    log "WARNING: some Nessus Agent components may remain - review $LOG"
    exit 1
fi
