#!/bin/bash
# ==============================================================================
# Jamf Connect Login Plugin - Ensure Minimum Version
# ==============================================================================
# The Jamf Connect *login window* plugin ships in the static JamfConnectLogin.pkg
# and does not auto-update — unlike the Jamf Connect app, which tracks the App
# Catalog. Worse, the only thing that invokes its install policy is Setup Manager
# at provisioning (trigger_other = "install-jamfconnect"), so an already-enrolled
# Mac keeps whatever plugin version it enrolled with, forever.
#
# That is how the fleet ended up running a plugin too old to honour
# SharedTokenTrustedApplications, which is what makes Self Service+ prompt for the
# login keychain password every time it reads the Jamf Connect shared token.
#
# This script closes that gap: on every check-in it compares the installed plugin
# version against a minimum and, if it is short, fires the existing install
# policy via its custom event. It is a cheap no-op once the fleet is current, so
# it is safe to run fleet-wide on an Ongoing policy.
#
# Parameters:
#   $4 = minimum acceptable plugin version (default 3.6 — per Jamf's KB, the
#        first release that honours SharedTokenTrustedApplications)
#   $5 = Jamf custom event that installs the pkg (default install-jamfconnect)
# ==============================================================================

set -uo pipefail

PLUGIN="/Library/Security/SecurityAgentPlugins/JamfConnectLogin.bundle"
MIN_VERSION="${4:-3.6}"
INSTALL_EVENT="${5:-install-jamfconnect}"
JAMF_BINARY="/usr/local/bin/jamf"

LOG="/var/log/jamf_connect_login.log"
STATUS_DIR="/Library/Application Support/Example/jamf-status"
STATUS_FILE="$STATUS_DIR/jamf-connect-login.status"

exec 3>&1
exec > >(tee -a "$LOG") 2>&1

log() { echo "$(date): $*"; }

STATE="UNKNOWN"
REASON=""
on_exit() {
    echo
    echo "=== jamf_connect_login.log (last 40 lines) ==="
    tail -40 "$LOG" >&3 2>/dev/null || true

    mkdir -p "$STATUS_DIR" 2>/dev/null || return 0
    printf '%s|%s|%s\n' \
        "$STATE" "$(date '+%Y-%m-%dT%H:%M:%S')" "${REASON:-}" \
        > "$STATUS_FILE" 2>/dev/null || true
}
trap on_exit EXIT

# Compare dot-separated numeric versions. Returns 0 when $1 >= $2.
# Deliberately not `sort -V` or a string compare: the login plugin versions run
# 3.5 -> 3.6 -> ... -> 3.25, where a lexical compare wrongly orders 3.25 < 3.6.
version_ge() {
    awk -v a="$1" -v b="$2" 'BEGIN {
        na = split(a, A, "."); nb = split(b, B, ".");
        n = (na > nb ? na : nb);
        for (i = 1; i <= n; i++) {
            x = (i <= na ? A[i] + 0 : 0);
            y = (i <= nb ? B[i] + 0 : 0);
            if (x > y) exit 0;
            if (x < y) exit 1;
        }
        exit 0
    }'
}

installed_version() {
    if [[ -d "$PLUGIN" ]]; then
        defaults read "$PLUGIN/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null
    fi
}

log "============================================"
log "Jamf Connect login plugin check (minimum $MIN_VERSION)"
log "============================================"

CURRENT=$(installed_version)
log "Installed plugin version: ${CURRENT:-none}"

if [[ -n "$CURRENT" ]] && version_ge "$CURRENT" "$MIN_VERSION"; then
    log "Plugin is at or above $MIN_VERSION — nothing to do"
    STATE="OK"
    REASON="plugin $CURRENT >= $MIN_VERSION"
    exit 0
fi

# ==============================================================================
# Below minimum (or absent) — install via the existing package policy
# ==============================================================================
if [[ ! -x "$JAMF_BINARY" ]]; then
    log "ERROR - jamf binary not found at $JAMF_BINARY; cannot trigger install"
    STATE="FAIL"
    REASON="jamf binary missing"
    exit 0
fi

log "Plugin ${CURRENT:-absent} is below $MIN_VERSION — triggering '$INSTALL_EVENT'"
"$JAMF_BINARY" policy -event "$INSTALL_EVENT" 2>&1 || \
    log "WARNING - 'jamf policy -event $INSTALL_EVENT' returned non-zero (continuing to re-check)"

NEW=$(installed_version)
log "Plugin version after install attempt: ${NEW:-none}"

if [[ -n "$NEW" ]] && version_ge "$NEW" "$MIN_VERSION"; then
    log "Plugin updated to $NEW"
    STATE="OK"
    REASON="upgraded ${CURRENT:-absent} -> $NEW"
    log "NOTE: the login window loads the plugin at next login, and the stale"
    log "      Jamf Connect keychain item still carries its original ACL — the"
    log "      keychain reset script runs next in this policy to clear it."
    exit 0
fi

# Deliberately exit 0 with a FAIL status rather than exit 1: this runs on an
# Ongoing check-in policy, so a non-zero exit would flag every Mac as Failed on
# every check-in while the package is still stale in Jamf. The status file keeps
# the failure visible without that noise.
if [[ "${NEW:-}" == "${CURRENT:-}" ]]; then
    log "ERROR - plugin version unchanged (${NEW:-absent}). The package behind"
    log "        '$INSTALL_EVENT' is most likely still the old build — confirm the"
    log "        new JamfConnectLogin.pkg was uploaded and that the policy points at it."
    STATE="FAIL"
    REASON="unchanged at ${NEW:-absent}, wanted >= $MIN_VERSION"
else
    log "ERROR - plugin is ${NEW:-absent}, still below $MIN_VERSION"
    STATE="FAIL"
    REASON="${NEW:-absent} < $MIN_VERSION"
fi

exit 0
