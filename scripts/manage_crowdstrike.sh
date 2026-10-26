#!/bin/bash
# manage_crowdstrike.sh
# Single-policy CrowdStrike lifecycle management.
#
# Execution order:
#   1. Already operational + correct CID → exit 0 (nothing to do)
#   2. Installed, sensor not running → apply CID, start daemon, verify
#   3. Not installed → download + install pkg via Jamf, apply CID, verify
#
# Parameters:
#   $4 — CID (Customer ID, e.g. ABCDEF...XYZ-12)
#   $5 — Provisioning token (optional; required only if tenant has
#        "Require provisioning tokens for installations" enabled)

CID="${4:-}"
PROVISIONING_TOKEN="${5:-}"
FALCONCTL="/Applications/Falcon.app/Contents/Resources/falconctl"
LAUNCHDAEMON="/Library/LaunchDaemons/com.crowdstrike.falcond.plist"
POLL_INTERVAL=15
MAX_WAIT=90

OS_VERSION=$(sw_vers -productVersion 2>/dev/null || echo "unknown")

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "========================================================="
log "CrowdStrike management"
log "macOS        : $OS_VERSION"
log "Architecture : $(uname -m)"
log "CID          : ${CID:-<not provided>}"
log "Token        : ${PROVISIONING_TOKEN:+<set>}"
log "========================================================="

if [ -z "$CID" ]; then
    log "ERROR: CID not provided (parameter4). Check policy configuration."
    exit 1 # jamf-ci: exit1-intentional
fi

# falconctl license takes CID as $1 and optional provisioning token as $2.
# Wrapped here so callers don't need to branch on whether a token is set.
apply_license() {
    if [ -n "$PROVISIONING_TOKEN" ]; then
        "$FALCONCTL" license "$CID" "$PROVISIONING_TOKEN" 2>&1
    else
        "$FALCONCTL" license "$CID" 2>&1
    fi
}

# ── Step 1: Check if already compliant ───────────────────────────────────────

if [ -f "$FALCONCTL" ]; then
    STATUS=$("$FALCONCTL" stats agent_info 2>&1)
    if echo "$STATUS" | grep -qiE "operational: true|state: connected"; then
        VERSION=$(echo "$STATUS" | grep -i "^version:" | awk '{print $2}')
        CURRENT_CID=$("$FALCONCTL" stats 2>&1 | grep -i "cid" | awk '{print $NF}' | head -1)
        BASE_CURRENT=$(echo "$CURRENT_CID" | tr '[:lower:]' '[:upper:]' | cut -d- -f1)
        BASE_EXPECTED=$(echo "$CID" | tr '[:lower:]' '[:upper:]' | cut -d- -f1)

        if [ -z "$BASE_CURRENT" ] || [ "$BASE_CURRENT" = "$BASE_EXPECTED" ]; then
            log "Sensor operational (version: ${VERSION:-unknown}). CID verified. Compliant."
            exit 0
        fi

        log "Sensor operational but wrong CID (current: $CURRENT_CID, expected: $CID)."
        log "Re-applying CID..."
        apply_license || true
        sleep 5
    fi
fi

# ── Step 2: Install pkg if falconctl is absent ────────────────────────────────

if [ ! -f "$FALCONCTL" ]; then
    log "CrowdStrike not installed. Downloading and installing FalconSensorMacOS.pkg..."
    /usr/local/bin/jamf install -package "FalconSensorMacOS.pkg" -target / -verbose 2>&1 | \
        while IFS= read -r line; do log "  [jamf] $line"; done

    if [ ! -f "$FALCONCTL" ]; then
        log "ERROR: falconctl not found after pkg install. Check distribution point and package name."
        exit 1 # jamf-ci: exit1-intentional
    fi

    log "Package installed. Applying CID..."
fi

# ── Step 3: Apply CID ─────────────────────────────────────────────────────────

LICENSE_OUT=$(apply_license)
LICENSE_EXIT=$?
log "falconctl license exit: $LICENSE_EXIT — $LICENSE_OUT"

# ── Step 4: Start daemon if not running ──────────────────────────────────────

if ! pgrep -x falcond > /dev/null 2>&1; then
    log "Starting sensor..."
    launchctl bootstrap system "$LAUNCHDAEMON" 2>/dev/null || true
    sleep 5
fi

# ── Step 5: Poll for operational ─────────────────────────────────────────────

log "Polling for operational status (max ${MAX_WAIT}s)..."
ELAPSED=0
while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
    STATUS=$("$FALCONCTL" stats agent_info 2>&1)
    if echo "$STATUS" | grep -qiE "operational: true|state: connected"; then
        VERSION=$(echo "$STATUS" | grep -i "^version:" | awk '{print $2}')
        log "CrowdStrike is operational (version: ${VERSION:-unknown})."
        exit 0
    fi
    log "  [${ELAPSED}s] Not yet operational — waiting ${POLL_INTERVAL}s..."
    sleep "$POLL_INTERVAL"
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

log "ERROR: Sensor did not become operational within ${MAX_WAIT}s."
"$FALCONCTL" stats agent_info 2>&1 | while IFS= read -r line; do log "  $line"; done
exit 1 # jamf-ci: exit1-intentional
