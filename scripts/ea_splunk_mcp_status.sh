#!/bin/bash
# Reports whether the Jamf-deployed Splunk MCP server actually AUTHENTICATES,
# not merely whether its config file was written. configure_splunk_mcp.sh sets
# splunk-mcp.status = OK the moment it writes managed-mcp.json, so that status
# stays OK even when the bearer token is the wrong kind and every MCP call 401s
# — which is exactly how a bad token (a static "Claude Tag" token instead of an
# encrypted MCP token, audience "mcp") shipped fleet-wide undetected. This EA
# closes that blind spot: it reads the endpoint + token Claude Code would use
# and runs the MCP `initialize` handshake against Splunk, reporting the real
# outcome.
#
# Results:
#   OK           handshake returned HTTP 200 — token authenticates
#   AUTH_FAIL    HTTP 401/403 — token rejected (bad / expired / wrong audience);
#                drives the "Splunk MCP - Auth Failing" smart group
#   UNREACHABLE  no HTTP response (offline / off-network / timeout / 5xx) —
#                transient, deliberately NOT flagged for remediation
#   NO_CONFIG    no managed-mcp.json splunk entry (Claude Code MCP not deployed)
#
# Runs as root at inventory. Guards on config presence first so machines without
# the MCP make no network call, and uses tight curl timeouts so recon never
# hangs. MCP_FILE is overridable purely so the bats suite can point it at a
# fixture; Jamf never sets it and it defaults to the real managed path.
set -u

MCP_FILE="${MCP_FILE:-/Library/Application Support/ClaudeCode/managed-mcp.json}"

if [ ! -f "$MCP_FILE" ]; then
    echo "<result>NO_CONFIG</result>"
    exit 0
fi

# Pull endpoint + token from the same file Claude Code reads. On any parse error
# or a missing splunk entry, both come back empty and we report NO_CONFIG.
URL=""
TOKEN=""
{ read -r URL; read -r TOKEN; } < <(
    /usr/bin/python3 - "$MCP_FILE" <<'PY'
import json, sys
try:
    srv = json.load(open(sys.argv[1]))["mcpServers"]["splunk"]
    print(srv["url"])
    print(srv["headers"]["Authorization"].split(None, 1)[1])
except Exception:
    print("")
    print("")
PY
)

if [ -z "$URL" ] || [ -z "$TOKEN" ]; then
    echo "<result>NO_CONFIG</result>"
    exit 0
fi

# A minimal MCP initialize call: harmless, read-only, and the exact handshake a
# client makes before it can list or run any tool — so a 200 here means the
# server Claude Code sees will actually connect.
CODE=$(/usr/bin/curl -sS -o /dev/null -w '%{http_code}' \
    --connect-timeout 5 --max-time 10 \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -X POST "$URL" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"jamf-ea","version":"1"}}}' \
    2>/dev/null)

case "$CODE" in
    200)     echo "<result>OK</result>" ;;
    401|403) echo "<result>AUTH_FAIL</result>" ;;
    *)       echo "<result>UNREACHABLE</result>" ;;
esac
exit 0
