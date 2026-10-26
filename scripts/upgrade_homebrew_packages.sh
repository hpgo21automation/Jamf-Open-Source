#!/bin/bash
# ==============================================================================
# Homebrew Weekly Upgrade
# ==============================================================================
# Upgrades all installed Homebrew packages under /opt/homebrew_srv
# ==============================================================================

set -euo pipefail

# Variables
SERVICE_USER="srv_mac"
HOMEBREW_PREFIX="/opt/homebrew_srv"
BREW_PATH="$HOMEBREW_PREFIX/bin/brew"
HOMEBREW_CACHE_DIR="$HOMEBREW_PREFIX/cache"
HOMEBREW_LOGS_DIR="$HOMEBREW_PREFIX/logs"
HOMEBREW_TEMP_DIR="$HOMEBREW_PREFIX/tmp"
HOMEBREW_SSL_DIR="$HOMEBREW_PREFIX/etc/ssl/certs"
LOG="/var/log/homebrew_upgrade.log"

# ==============================================================================
# Last-run status reporting (read by the "Homebrew Upgrade Status" EA)
# Writes STATE|timestamp|reason to a status file so the daily compliance check
# can read the real outcome from inventory instead of only Jamf's Failed flag.
# ==============================================================================
STATUS_DIR="/Library/Application Support/Example/jamf-status"
STATUS_FILE="$STATUS_DIR/homebrew-upgrade.status"
STATUS_WRITTEN=0
write_status() {
    mkdir -p "$STATUS_DIR" 2>/dev/null || return 0
    printf '%s|%s|%s\n' "$1" "$(date '+%Y-%m-%dT%H:%M:%S')" "$2" \
        > "$STATUS_FILE" 2>/dev/null || true
    STATUS_WRITTEN=1
}
on_exit() {
    local rc=$?
    # Catch-all: only fires if the script aborted (set -e) before writing its
    # own summary status. A clean run records OK/partial explicitly below.
    [[ "$STATUS_WRITTEN" == "1" ]] && return
    if [[ $rc -eq 0 ]]; then
        write_status "OK" ""
    else
        write_status "FAIL" "aborted (exit $rc) — see $LOG"
    fi
}
trap on_exit EXIT

echo "============================================" >> "$LOG"
echo "$(date): Homebrew Weekly Upgrade" >> "$LOG"
echo "============================================" >> "$LOG"

# ==============================================================================
# Retired-package status-marker cleanup
# ==============================================================================
# When a Homebrew package is retired from management (enabled = false in
# homebrew.auto.tfvars), its per-formula install/remediation policy stops
# running, so the FAIL marker that homebrew_package_installer.sh wrote on its
# last failed run is never updated or removed. That orphaned marker keeps the
# device pinned in the "Homebrew Install - Failing" smart group forever, because
# the "Homebrew Install Failures" EA (ea_homebrew_install_failures.sh) just reads
# these files. Flushing Jamf policy logs does NOT touch them — only the device
# can. Clear the markers for formulas we have intentionally retired so affected
# devices leave the smart group on their next inventory. Mirrors the stale-marker
# cleanup in install_logi_options.sh (#115).
#
# Only list a formula here once its package entry is enabled = false in
# homebrew.auto.tfvars — removing a live package's marker would mask a real
# failure. Runs before the srv_mac/brew guards below so it still fires on hosts
# where those short-circuit.
RETIRED_FORMULAS=(
    "kubens"                     # disabled #153 — ships with the "kubectx" formula
    "docker-credential-gcloud"   # disabled #153 — ships with the Google Cloud CLI
)
for RETIRED_FORMULA in "${RETIRED_FORMULAS[@]}"; do
    RETIRED_MARKER="$STATUS_DIR/homebrew-install-${RETIRED_FORMULA}.status"
    if [[ -e "$RETIRED_MARKER" ]]; then
        if rm -f "$RETIRED_MARKER" 2>/dev/null; then
            echo "$(date): Removed orphaned status marker for retired formula: $RETIRED_FORMULA" >> "$LOG"
        else
            echo "$(date): WARN - failed to remove orphaned marker: $RETIRED_MARKER" >> "$LOG"
        fi
    fi
done

# Check if srv_mac exists
if ! id "$SERVICE_USER" &>/dev/null; then
    echo "$(date): ERROR - User $SERVICE_USER does not exist" >> "$LOG"
    exit 1
fi

# Check if Homebrew is installed
if [[ ! -x "$BREW_PATH" ]]; then
    echo "$(date): Homebrew not installed at $BREW_PATH, skipping" >> "$LOG"
    exit 0
fi

# Ensure required directories exist. Guard each step so a transient chown/chmod
# error can't abort the whole upgrade under `set -e` (these are best-effort:
# Homebrew works regardless of exact ownership of its cache/log/tmp dirs).
for DIR in "$HOMEBREW_CACHE_DIR" "$HOMEBREW_LOGS_DIR" "$HOMEBREW_TEMP_DIR"; do
    if [[ ! -d "$DIR" ]]; then
        mkdir -p "$DIR" || true
        chown "$SERVICE_USER:staff" "$DIR" 2>/dev/null || true
        chmod 750 "$DIR" 2>/dev/null || true
    fi
done

# ==============================================================================
# Determine CA certificate bundle location
# ==============================================================================
get_ca_bundle() {
    local COMBINED_BUNDLE="$HOMEBREW_SSL_DIR/ca-bundle.pem"

    if [[ -f "$COMBINED_BUNDLE" ]]; then
        echo "$COMBINED_BUNDLE"
    elif [[ -f "$HOMEBREW_PREFIX/etc/ca-certificates/cert.pem" ]]; then
        echo "$HOMEBREW_PREFIX/etc/ca-certificates/cert.pem"
    elif [[ -f "$HOMEBREW_PREFIX/etc/openssl@3/cert.pem" ]]; then
        echo "$HOMEBREW_PREFIX/etc/openssl@3/cert.pem"
    elif [[ -f "/etc/ssl/cert.pem" ]]; then
        echo "/etc/ssl/cert.pem"
    else
        echo ""
    fi
}

# ==============================================================================
# Function to run brew as service user with proper environment
# ==============================================================================
run_brew() {
    local XML_CATALOGS="$HOMEBREW_PREFIX/etc/xml/catalog"
    if [[ -f "/etc/xml/catalog" ]]; then
        XML_CATALOGS="$XML_CATALOGS:/etc/xml/catalog"
    fi

    local CA_BUNDLE
    CA_BUNDLE=$(get_ca_bundle)

    local ISRG_CERT="$HOMEBREW_SSL_DIR/isrg-root-x1.pem"
    local NODE_CA_CERTS=""
    if [[ -f "$ISRG_CERT" ]]; then
        NODE_CA_CERTS="$ISRG_CERT"
    elif [[ -n "$CA_BUNDLE" ]]; then
        NODE_CA_CERTS="$CA_BUNDLE"
    fi

    local ENV_VARS=(
        HOME="$HOMEBREW_PREFIX"
        HOMEBREW_CACHE="$HOMEBREW_CACHE_DIR"
        HOMEBREW_LOGS="$HOMEBREW_LOGS_DIR"
        HOMEBREW_TEMP="$HOMEBREW_TEMP_DIR"
        HOMEBREW_NO_AUTO_UPDATE=1
        HOMEBREW_NO_ANALYTICS=1
        HOMEBREW_NO_ENV_HINTS=1
        XML_CATALOG_FILES="$XML_CATALOGS"
    )

    if [[ -n "$CA_BUNDLE" ]]; then
        ENV_VARS+=(
            SSL_CERT_FILE="$CA_BUNDLE"
            SSL_CERT_DIR="$(dirname "$CA_BUNDLE")"
            REQUESTS_CA_BUNDLE="$CA_BUNDLE"
            CURL_CA_BUNDLE="$CA_BUNDLE"
        )
    fi

    if [[ -n "$NODE_CA_CERTS" ]]; then
        ENV_VARS+=(
            NODE_EXTRA_CA_CERTS="$NODE_CA_CERTS"
        )
    fi

    sudo -u "$SERVICE_USER" "${ENV_VARS[@]}" "$BREW_PATH" "$@"
}

# ==============================================================================
# Update Homebrew
# ==============================================================================
echo "$(date): Updating Homebrew..." >> "$LOG"
if run_brew update >> "$LOG" 2>&1; then
    echo "$(date): Homebrew updated successfully" >> "$LOG"
else
    echo "$(date): Homebrew update warning (continuing)" >> "$LOG"
fi

# ==============================================================================
# Check for outdated packages
# ==============================================================================
echo "$(date): Checking for outdated packages..." >> "$LOG"
OUTDATED=$(run_brew outdated 2>/dev/null) || true

if [[ -z "$OUTDATED" ]]; then
    echo "$(date): All packages are up to date" >> "$LOG"
    echo "All packages are up to date"
    exit 0
fi

echo "$(date): Outdated packages:" >> "$LOG"
echo "$OUTDATED" >> "$LOG"

# ==============================================================================
# Upgrade all packages
# ==============================================================================
echo "$(date): Upgrading packages..." >> "$LOG"
UPGRADED=0
FAILED=0
FAILED_LIST=()

if run_brew upgrade >> "$LOG" 2>&1; then
    echo "$(date): All packages upgraded successfully" >> "$LOG"
else
    echo "$(date): Some packages may have failed to upgrade" >> "$LOG"
fi

# Check what's still outdated after upgrade
STILL_OUTDATED=$(run_brew outdated 2>/dev/null) || true
if [[ -n "$STILL_OUTDATED" ]]; then
    while IFS= read -r pkg; do
        FAILED_LIST+=("$pkg")
        # Use $((...)) assignment instead of ((FAILED++)) because the C-style
        # post-increment returns the OLD value (0 on first iteration), and
        # ((expr)) returns exit status 1 when expr is 0 — which aborts the
        # whole script under `set -e` before any cleanup or summary runs.
        FAILED=$((FAILED + 1))
    done <<< "$STILL_OUTDATED"
fi

# Count upgraded packages
TOTAL_OUTDATED=$(echo "$OUTDATED" | wc -l | tr -d ' ')
UPGRADED=$((TOTAL_OUTDATED - FAILED))

# ==============================================================================
# Cleanup old versions
# ==============================================================================
echo "$(date): Cleaning up old versions..." >> "$LOG"
run_brew cleanup --prune=7 >> "$LOG" 2>&1 || echo "$(date): Cleanup warning (continuing)" >> "$LOG"

# ==============================================================================
# Summary
# ==============================================================================
echo "============================================" >> "$LOG"
echo "$(date): Upgrade Summary" >> "$LOG"
echo "============================================" >> "$LOG"
echo "Packages upgraded: $UPGRADED" >> "$LOG"
echo "Packages failed: $FAILED" >> "$LOG"
if [[ ${#FAILED_LIST[@]} -gt 0 ]]; then
    echo "Failed: ${FAILED_LIST[*]}" >> "$LOG"
fi
echo "============================================" >> "$LOG"

echo ""
echo "============================================"
echo "Homebrew Upgrade Complete"
echo "============================================"
echo "Upgraded: $UPGRADED | Failed: $FAILED"
if [[ ${#FAILED_LIST[@]} -gt 0 ]]; then
    echo "Failed: ${FAILED_LIST[*]}"
fi
echo "Full log: $LOG"
echo "============================================"

# Record outcome for the "Homebrew Upgrade Status" EA. Packages that fail to
# upgrade are surfaced here WITHOUT failing the policy (exit 0): a single stuck
# formula shouldn't flip the whole device to Failed — the EA carries the detail.
if [[ $FAILED -gt 0 ]]; then
    write_status "FAIL" "$FAILED package(s) still outdated: ${FAILED_LIST[*]}"
else
    write_status "OK" "upgraded $UPGRADED"
fi

exit 0
