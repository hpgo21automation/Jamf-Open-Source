#!/bin/bash
# ci-unmanaged: one-time cleanup script — not deployed via Terraform, run manually via Jamf Remote
# ==============================================================================
# Remove Partial Wireshark Homebrew Installation
# ==============================================================================
# Cleans up any partial wireshark formula installation and its build
# dependencies (libidn2, p11-kit, unbound, texinfo, gnutls) that may have
# been left behind from a failed brew install attempt under /opt/homebrew_srv.
# ==============================================================================

set -uo pipefail

SERVICE_USER="srv_mac"
HOMEBREW_PREFIX="/opt/homebrew_srv"
BREW_PATH="$HOMEBREW_PREFIX/bin/brew"
LOG="/var/log/homebrew_installs.log"

PACKAGES_TO_REMOVE=(wireshark gnutls unbound p11-kit libidn2 texinfo)

echo "============================================" >> "$LOG"
echo "$(date): Wireshark Homebrew Cleanup" >> "$LOG"
echo "============================================" >> "$LOG"

if [[ ! -x "$BREW_PATH" ]]; then
    echo "$(date): Homebrew not found at $BREW_PATH — nothing to clean up" >> "$LOG"
    exit 0
fi

if ! id "$SERVICE_USER" &>/dev/null; then
    echo "$(date): User $SERVICE_USER does not exist — nothing to clean up" >> "$LOG"
    exit 0
fi

run_brew() {
    sudo -u "$SERVICE_USER" \
        HOME="$HOMEBREW_PREFIX" \
        HOMEBREW_CACHE="$HOMEBREW_PREFIX/cache" \
        HOMEBREW_LOGS="$HOMEBREW_PREFIX/logs" \
        HOMEBREW_TEMP="$HOMEBREW_PREFIX/tmp" \
        HOMEBREW_NO_AUTO_UPDATE=1 \
        HOMEBREW_NO_ENV_HINTS=1 \
        "$BREW_PATH" "$@"
}

REMOVED_ANY=false

for pkg in "${PACKAGES_TO_REMOVE[@]}"; do
    if run_brew list "$pkg" &>/dev/null 2>&1; then
        echo "$(date): Removing $pkg..." >> "$LOG"
        if run_brew uninstall --ignore-dependencies "$pkg" >> "$LOG" 2>&1; then
            echo "$(date): Removed $pkg" >> "$LOG"
            REMOVED_ANY=true
        else
            echo "$(date): WARNING - Could not remove $pkg (may have dependents)" >> "$LOG"
        fi
    else
        echo "$(date): $pkg not installed — skipping" >> "$LOG"
    fi
done

# Clean up partial build artifacts and cached downloads
echo "$(date): Running brew cleanup..." >> "$LOG"
run_brew cleanup --prune=all >> "$LOG" 2>&1 || true

# Remove any leftover wireshark source/build dirs from tmp
if [[ -d "$HOMEBREW_PREFIX/tmp" ]]; then
    find "$HOMEBREW_PREFIX/tmp" -maxdepth 1 -name "wireshark*" -exec rm -rf {} + 2>/dev/null || true
    find "$HOMEBREW_PREFIX/tmp" -maxdepth 1 -name "gnutls*" -exec rm -rf {} + 2>/dev/null || true
    find "$HOMEBREW_PREFIX/tmp" -maxdepth 1 -name "unbound*" -exec rm -rf {} + 2>/dev/null || true
    echo "$(date): Cleaned up partial build artifacts from tmp" >> "$LOG"
fi

if [[ "$REMOVED_ANY" == "true" ]]; then
    echo "$(date): SUCCESS - Wireshark homebrew cleanup complete" >> "$LOG"
else
    echo "$(date): Nothing to remove — Wireshark was not installed via Homebrew" >> "$LOG"
fi

echo "============================================" >> "$LOG"

exit 0
