#!/bin/bash
# ==============================================================================
# Deploy the Splunk MCP server to Claude Code via enterprise managed config
# ==============================================================================
# Parameters:
#   $4 = MCP endpoint URL
#   $5 = Splunk MCP encrypted token (audience "mcp")
#
# Claude Code cannot be configured by a configuration profile the way Cursor and
# iTerm2 are: it does not read CFPreferences, so there is no preference domain
# for a .mobileconfig payload to write. Its equivalent of a managed profile is a
# pair of root-owned files under /Library/Application Support/ClaudeCode:
#
#   managed-mcp.json       enterprise MCP server definitions (this is where the
#                          Splunk server goes — "mcpServers" is NOT a valid key
#                          in managed-settings.json)
#   managed-settings.json  policy settings, highest precedence, not user-overridable
#
# Deploying managed-mcp.json puts Claude Code into exclusive-control lockdown:
# claude.ai cloud connectors are suppressed unless allowAllClaudeAiMcps is set in
# managed settings. Engineers here rely on those connectors, so this script sets
# that flag to preserve them. Set MCP_EXCLUSIVE=1 to opt into the lockdown and
# make the managed list the only MCP servers available fleet-wide.
#
# System-level, so it applies to every user on the Mac and works before anyone
# has logged in — no console-user dependency and no per-user file to merge.
# ==============================================================================

set -uo pipefail

ENDPOINT="${4:-}"
MCP_TOKEN="${5:-}"
SERVER_NAME="splunk"
EXCLUSIVE="${MCP_EXCLUSIVE:-0}"

MANAGED_DIR="/Library/Application Support/ClaudeCode"
MCP_FILE="$MANAGED_DIR/managed-mcp.json"
SETTINGS_FILE="$MANAGED_DIR/managed-settings.json"

LOG="/var/log/splunk_mcp_config.log"
STATUS_DIR="/Library/Application Support/Example/jamf-status"
STATUS_FILE="$STATUS_DIR/splunk-mcp.status"

exec 3>&1
exec > >(tee -a "$LOG") 2>&1

log() { echo "$(date): $*"; }

STATE="UNKNOWN"
REASON=""
on_exit() {
    echo
    echo "=== splunk_mcp_config.log (last 30 lines) ==="
    tail -30 "$LOG" >&3 2>/dev/null || true
    mkdir -p "$STATUS_DIR" 2>/dev/null || true
    printf '%s|%s|%s\n' "$STATE" "$(date '+%Y-%m-%dT%H:%M:%S')" "${REASON:-}" \
        > "$STATUS_FILE" 2>/dev/null || true
}
trap on_exit EXIT

log "============================================"
log "Deploy Splunk MCP server (managed config)"
log "============================================"

if [[ -z "$ENDPOINT" ]] || [[ -z "$MCP_TOKEN" ]]; then
    log "ERROR - endpoint (parameter 4) and token (parameter 5) are both required"
    STATE="FAIL"; REASON="missing endpoint or token parameter"
    exit 1 # jamf-ci: exit1-intentional
fi
log "Endpoint: $ENDPOINT"
log "Exclusive lockdown: $([[ "$EXCLUSIVE" == "1" ]] && echo "on — managed servers only" || echo "off — claude.ai connectors preserved")"

mkdir -p "$MANAGED_DIR"

# The token is passed through the environment, never argv, so it does not appear
# in the process list.
export MCP_ENDPOINT="$ENDPOINT" MCP_TOKEN MCP_FILE SETTINGS_FILE SERVER_NAME EXCLUSIVE

RESULT=$(/usr/bin/python3 <<'PY'
import json, os, tempfile

def load(path):
    if not os.path.exists(path):
        return {}, True
    try:
        with open(path) as fh:
            return json.load(fh), True
    except (ValueError, OSError):
        return None, False

def write(path, data):
    directory = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".tmp-")
    with os.fdopen(fd, "w") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    os.replace(tmp, path)
    # World-readable on purpose: Claude Code reads these as the logged-in user.
    os.chmod(path, 0o644)
    os.chown(path, 0, 0)

changed = []

# --- managed-mcp.json: the server definition ------------------------------
mcp_path = os.environ["MCP_FILE"]
name = os.environ["SERVER_NAME"]
desired = {
    "type": "http",
    "url": os.environ["MCP_ENDPOINT"],
    "headers": {"Authorization": "Bearer " + os.environ["MCP_TOKEN"]},
}

mcp, ok = load(mcp_path)
if not ok:
    print("ERROR|managed-mcp.json exists but is not valid JSON — leaving it alone")
    raise SystemExit(2)

servers = mcp.setdefault("mcpServers", {})
if servers.get(name) != desired:
    servers[name] = desired
    write(mcp_path, mcp)
    changed.append("managed-mcp.json")

# --- managed-settings.json: keep claude.ai connectors unless locking down ---
settings_path = os.environ["SETTINGS_FILE"]
settings, ok = load(settings_path)
if not ok:
    print("ERROR|managed-settings.json exists but is not valid JSON — leaving it alone")
    raise SystemExit(2)

want_connectors = os.environ.get("EXCLUSIVE") != "1"
if settings.get("allowAllClaudeAiMcps") != want_connectors:
    settings["allowAllClaudeAiMcps"] = want_connectors
    write(settings_path, settings)
    changed.append("managed-settings.json")

print(("UPDATED|" + ", ".join(changed)) if changed else "UNCHANGED|already current")
PY
)
RC=$?

log "Result: ${RESULT:-<no output>}"

case "${RESULT%%|*}" in
    UNCHANGED)
        STATE="OK"; REASON="already current"
        log "No change needed"
        ;;
    UPDATED)
        STATE="OK"; REASON="wrote ${RESULT#*|}"
        log "Wrote ${RESULT#*|}"
        log "Users must restart Claude Code to pick this up."
        ;;
    *)
        STATE="FAIL"; REASON="${RESULT#*|}"
        log "ERROR - failed to write managed config (exit $RC)"
        exit 1 # jamf-ci: exit1-intentional
        ;;
esac

exit 0
