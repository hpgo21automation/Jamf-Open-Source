#!/bin/bash
# configure_docker.sh
# Installs Docker Desktop privileged components to avoid first-run password prompt.
#
# Detects already-installed privileged helpers across Docker Desktop path
# generations and short-circuits (idempotent). Docker >= 4.35 has no helper
# (user-space networking), so it exits 0 without installing. Per-fix history
# is in git; inline notes below mark the version-specific edge cases.

DOCKER_APP="/Applications/Docker.app"
CURRENT_USER=$(stat -f "%Su" /dev/console)
ADMIN_SETTINGS="/Library/Application Support/com.docker.docker/admin-settings.json"

# Exit if Docker is not installed
if [ ! -d "$DOCKER_APP" ]; then
    echo "[path: docker-not-installed] Docker Desktop not installed, exiting."
    exit 0
fi

# Exit if no user logged in
if [ -z "$CURRENT_USER" ] || [ "$CURRENT_USER" = "root" ]; then
    echo "[path: no-user] No user logged in, exiting."
    exit 0
fi

DOCKER_VERSION=$(defaults read /Applications/Docker.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo "unknown")
echo "====================================================="
echo "Docker Desktop version : $DOCKER_VERSION"
echo "Current user           : $CURRENT_USER"
echo "====================================================="

# ─────────────────────────────────────────────────────────────────────────────
# FIX: Docker 4.35+ version gate
#
# Docker Desktop 4.35 (Nov 2024) removed vmnetd and all privileged helpers,
# switching to user-space networking via Apple's Virtualization.framework.
# On these versions:
#   - No privileged helper is installed or expected
#   - The install binary may be absent (handled by the missing-binary guard
#     added in #49) or present but unable to install helpers (exits non-zero)
#   - Attempting installation causes spurious policy failures with no benefit
#
# Version comparison: split on '.' and compare major.minor numerically.
# Returns 0 (true) if Docker version needs helper install (< 4.35).
# Returns 1 (false, skip install) if Docker >= 4.35.
# ─────────────────────────────────────────────────────────────────────────────
docker_needs_helper_install() {
    local version="$1"
    local major minor
    major=$(echo "$version" | cut -d. -f1)
    minor=$(echo "$version" | cut -d. -f2)

    # Can't parse version — assume install is needed (safe default)
    if [ -z "$major" ] || [ -z "$minor" ]; then
        echo "WARNING: Could not parse Docker version '$version' — assuming helper install needed"
        return 0
    fi

    # Docker 5.x+ — definitely no helpers needed
    if [ "$major" -gt 4 ] 2>/dev/null; then
        return 1
    fi

    # Docker 4.35+ — user-space networking, no helpers needed
    if [ "$major" -eq 4 ] && [ "$minor" -ge 35 ] 2>/dev/null; then
        return 1
    fi

    return 0
}

if ! docker_needs_helper_install "$DOCKER_VERSION"; then
    echo "[path: version-gate-exit0] Docker Desktop $DOCKER_VERSION uses user-space networking (>= 4.35)."
    echo "Privileged helper installation is not needed or supported on this version."
    exit 0
fi

echo "[path: needs-helper-install] Docker $DOCKER_VERSION is < 4.35 — proceeding with helper install check."

# ─────────────────────────────────────────────────────────────────────────────
# Check if privileged components are installed across all known generations:
#   Legacy (Docker < 4.35):  com.docker.vmnetd helper + LaunchDaemon
#   Socket-based (Docker 4.x): com.docker.socket helper
#   Backend helper (some 4.x): com.docker.backend.privileged
#   Wildcard: any com.docker.* LaunchDaemon (future versions)
# ─────────────────────────────────────────────────────────────────────────────
privileged_components_installed() {
    [ -f "/Library/PrivilegedHelperTools/com.docker.vmnetd" ] && return 0
    [ -f "/Library/LaunchDaemons/com.docker.vmnetd.plist" ] && return 0
    [ -f "/Library/PrivilegedHelperTools/com.docker.socket" ] && return 0
    [ -f "/Library/PrivilegedHelperTools/com.docker.backend.privileged" ] && return 0
    # SC2010: use glob + -e test instead of ls|grep
    for _plist in /Library/LaunchDaemons/com.docker.*.plist; do
        [ -e "$_plist" ] && return 0
    done
    return 1
}

log_docker_helper_state() {
    local label="$1"
    echo "--- Docker helper paths ($label) ---"
    ls -la /Library/PrivilegedHelperTools/com.docker.* 2>/dev/null || echo "  /Library/PrivilegedHelperTools: no com.docker.* files"
    ls -la /Library/LaunchDaemons/com.docker.* 2>/dev/null || echo "  /Library/LaunchDaemons: no com.docker.* plists"
    launchctl list 2>/dev/null | grep -i docker || echo "  launchctl: no docker services running"
    echo "---"
}

# Short-circuit: nothing to do if already installed
if privileged_components_installed; then
    echo "[path: already-installed] Privileged components already installed — nothing to do."
    log_docker_helper_state "already-present"
    exit 0
fi

log_docker_helper_state "before-install"

# Remove any existing admin-settings.json that might interfere
if [ -f "$ADMIN_SETTINGS" ]; then
    echo "Removing existing admin-settings.json..."
    rm -f "$ADMIN_SETTINGS"
fi

# Kill Docker if running.
# FIX (2026-04-29): increased from 2s to 10s — M4 devices running macOS 15
# have higher teardown latency for Docker's VM processes; a stale helper socket
# still open after 2s causes the install binary to exit non-zero immediately.
pkill -f "Docker Desktop" 2>/dev/null
pkill -f "com.docker" 2>/dev/null
echo "Waiting 10s for Docker processes to fully terminate..."
sleep 10

# FIX (#49): Guard against missing install binary.
DOCKER_INSTALL="$DOCKER_APP/Contents/MacOS/install"
if [ ! -f "$DOCKER_INSTALL" ]; then
    echo "[path: no-install-binary] Docker install binary not found at $DOCKER_INSTALL"
    echo "Installed Docker Desktop version: $DOCKER_VERSION"
    echo "This Docker Desktop version may manage privileged helpers differently."
    echo "Exiting 0 — helper installation is expected to be handled by Docker Desktop on first launch."
    exit 0
fi

echo "[path: running-install] Install binary found at $DOCKER_INSTALL"
echo "Docker Desktop version: $DOCKER_VERSION"

# ─────────────────────────────────────────────────────────────────────────────
# FIX (2026-04-29): Three-attempt install strategy
#
# Docker 4.30-4.34 on macOS 15 uses SMJobBless for helper authorization.
# SMJobBless requires the calling process to have a valid authorization ref
# from the Security framework. When Jamf runs scripts as root via launchd,
# the authorization context may lack the interactive session needed for
# SMJobBless on some macOS 15 builds. Running via `launchctl asuser` places
# the process in the logged-in user's launchd session, which has the
# necessary authorization context.
#
# Attempt order:
#   1. Root context, --install-privileged-components flag (classic, works on
#      most Docker 4.x and all Docker 3.x)
#   2. User context via launchctl asuser, same flag (macOS 15 + Docker 4.30+)
#   3. Root context, no flags (legacy fallback for older Docker 4.x builds)
# ─────────────────────────────────────────────────────────────────────────────
INSTALL_EXIT=1
INSTALL_OUTPUT_FILE=$(mktemp /tmp/docker_install_output.XXXXXX)
CURRENT_UID=$(id -u "$CURRENT_USER" 2>/dev/null || echo "")

# Attempt 1: root + flag
echo "[install-attempt 1/3] Root context with --install-privileged-components..."
"$DOCKER_INSTALL" --install-privileged-components 2>&1 | tee "$INSTALL_OUTPUT_FILE"
FIRST_EXIT=${PIPESTATUS[0]}
echo "Attempt 1 exit: $FIRST_EXIT"

if [ $FIRST_EXIT -eq 0 ]; then
    INSTALL_EXIT=0
    echo "Attempt 1 succeeded."
else
    # Attempt 2: user context + flag (requires CURRENT_UID)
    if [ -n "$CURRENT_UID" ]; then
        echo "[install-attempt 2/3] User context (launchctl asuser $CURRENT_UID) with --install-privileged-components..."
        launchctl asuser "$CURRENT_UID" "$DOCKER_INSTALL" --install-privileged-components 2>&1 | tee -a "$INSTALL_OUTPUT_FILE"
        USER_EXIT=${PIPESTATUS[0]}
        echo "Attempt 2 exit: $USER_EXIT"
        if [ $USER_EXIT -eq 0 ]; then
            INSTALL_EXIT=0
            echo "Attempt 2 succeeded."
        fi
    else
        echo "[install-attempt 2/3] Skipped — could not resolve UID for user '$CURRENT_USER'"
    fi

    # Attempt 3: root, no flags
    if [ $INSTALL_EXIT -ne 0 ]; then
        echo "[install-attempt 3/3] Root context, no flags..."
        "$DOCKER_INSTALL" 2>&1 | tee -a "$INSTALL_OUTPUT_FILE"
        INSTALL_EXIT=${PIPESTATUS[0]}
        echo "Attempt 3 exit: $INSTALL_EXIT"
    fi
fi

rm -f "$INSTALL_OUTPUT_FILE"
echo "Docker install command final exit code: $INSTALL_EXIT"

# Give components a moment to be written to disk
sleep 2

log_docker_helper_state "after-install"

# Success if any generation of helper is now present
if privileged_components_installed; then
    echo "[path: success] Privileged components confirmed installed."
    exit 0
fi

# Trust the install command's own exit code: if it reported success but helpers
# aren't at any known path, assume a future Docker version changed locations
if [ $INSTALL_EXIT -eq 0 ]; then
    echo "[path: trust-exit0] Install command exited 0 — treating as success (helper paths may differ)."
    exit 0
fi

echo "[path: failure] ERROR: Docker privileged helper installation failed."
echo "  Docker version : $DOCKER_VERSION"
echo "  Install exit   : $INSTALL_EXIT"
echo "  No helper files found at any known path (see 'after-install' listing above)"
echo "  NEXT STEPS: Check the install output above for the specific error message."
echo "  If Docker was recently updated to >= 4.35, verify the version gate logic above."
exit 1 # jamf-ci: exit1-intentional — re-runs on next Ongoing policy check
