#!/bin/bash
# ==============================================================================
# Jamf Connect - Reset Keychain ACL
# ==============================================================================
# Deletes the stale "Jamf Connect" login-keychain item so the login plugin
# recreates it with a correct access control list.
#
# Why this is needed on top of updating the plugin: a keychain item's ACL is
# stamped when the item is created and is never retro-fitted. On this fleet the
# existing items list only Apple's authorizationhost bundles as trusted
# applications, so Jamf Connect's own password-sync path (which runs inside
# authorizationhost) reads the shared token silently while Self Service+ — not on
# the list — must prompt for the login keychain password every single time.
# Updating the plugin fixes newly created items only; the old item has to go.
#
# Guards:
#   * a console user must be logged in (the item lives in their login keychain)
#   * the plugin must already meet the minimum version, otherwise the item would
#     just be recreated with the same broken ACL
#   * a per-user, per-plugin-version marker keeps this one-shot
#
# Cost: Jamf Connect asks the user for their password once at next sign-in as it
# repopulates the item. That is a single prompt in place of a recurring one.
#
# Parameters:
#   $4 = minimum acceptable plugin version (default 3.6)
# ==============================================================================

set -uo pipefail

PLUGIN="/Library/Security/SecurityAgentPlugins/JamfConnectLogin.bundle"
MIN_VERSION="${4:-3.6}"
KEYCHAIN_SERVICE="Jamf Connect"

LOG="/var/log/jamf_connect_login.log"
STATUS_DIR="/Library/Application Support/Example/jamf-status"
STATUS_FILE="$STATUS_DIR/jamf-connect-keychain.status"
MARKER_DIR="$STATUS_DIR/jc-keychain-reset"

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

# See update_jamf_connect_login.sh — lexical compare mis-orders 3.25 vs 3.6.
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

log "============================================"
log "Jamf Connect keychain ACL reset"
log "============================================"

# ==============================================================================
# Guard: plugin must already be new enough
# ==============================================================================
CURRENT=""
if [[ -d "$PLUGIN" ]]; then
    CURRENT=$(defaults read "$PLUGIN/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)
fi

if [[ -z "$CURRENT" ]]; then
    log "Login plugin not installed — nothing to reset"
    STATE="SKIP"
    REASON="plugin not installed"
    exit 0
fi

if ! version_ge "$CURRENT" "$MIN_VERSION"; then
    log "Plugin $CURRENT is below $MIN_VERSION — skipping."
    log "Resetting now would only recreate the item with the same broken ACL."
    STATE="SKIP"
    REASON="plugin $CURRENT < $MIN_VERSION"
    exit 0
fi
log "Plugin version $CURRENT meets minimum $MIN_VERSION"

# ==============================================================================
# Guard: need a logged-in console user
# ==============================================================================
CONSOLE_USER=$(stat -f%Su /dev/console 2>/dev/null)
if [[ -z "$CONSOLE_USER" ]] || [[ "$CONSOLE_USER" == "root" ]]; then
    log "No console user logged in — will retry on a later run"
    STATE="SKIP"
    REASON="no console user"
    exit 0
fi

CONSOLE_UID=$(id -u "$CONSOLE_USER" 2>/dev/null)
if [[ -z "$CONSOLE_UID" ]]; then
    log "Could not resolve uid for $CONSOLE_USER — skipping"
    STATE="SKIP"
    REASON="no uid for $CONSOLE_USER"
    exit 0
fi
log "Console user: $CONSOLE_USER (uid $CONSOLE_UID)"

# ==============================================================================
# Guard: one-shot per user per plugin version
# ==============================================================================
mkdir -p "$MARKER_DIR" 2>/dev/null || true
MARKER="$MARKER_DIR/${CONSOLE_USER}-${CURRENT}.done"
if [[ -f "$MARKER" ]]; then
    log "Already reset for $CONSOLE_USER on plugin $CURRENT — nothing to do"
    STATE="OK"
    REASON="already reset for $CONSOLE_USER on $CURRENT"
    exit 0
fi

# ==============================================================================
# Delete the item(s)
# ==============================================================================
# Run inside the user's GUI session: the login keychain is unlocked there, so the
# delete is silent. `sudo -u` alone lacks the session context.
run_as_user() {
    launchctl asuser "$CONSOLE_UID" sudo -u "$CONSOLE_USER" "$@"
}

DELETED=0
# There may be more than one item for the service; delete-generic-password
# removes a single match per call, so loop until none are left.
for _ in 1 2 3 4 5 6 7 8 9 10; do
    if run_as_user security delete-generic-password -s "$KEYCHAIN_SERVICE" >/dev/null 2>&1; then
        DELETED=$((DELETED + 1))
    else
        break
    fi
done

if [[ $DELETED -eq 0 ]]; then
    log "No '$KEYCHAIN_SERVICE' item found in ${CONSOLE_USER}'s login keychain"
    log "(already cleared, or Jamf Connect has not created it yet)"
    STATE="OK"
    REASON="no item to delete for $CONSOLE_USER"
else
    log "Deleted $DELETED '$KEYCHAIN_SERVICE' keychain item(s) for $CONSOLE_USER"
    log "Jamf Connect will recreate it at next sign-in, with Self Service+ in the ACL."
    log "The user is prompted for their password once during that first recreate."
    STATE="OK"
    REASON="deleted $DELETED item(s) for $CONSOLE_USER on plugin $CURRENT"
fi

touch "$MARKER" 2>/dev/null || true

exit 0
