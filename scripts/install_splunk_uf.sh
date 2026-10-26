#!/bin/bash
###############################################################################
# Splunk Universal Forwarder Installation & Configuration for Example
#
# Installs or upgrades the Splunk Universal Forwarder (darwin-arm64 — the fleet
# is all Apple Silicon) and installs the Splunk Cloud credentials package.
#
# Target version + download URL are pinned in Terraform (locals.splunk_target_*)
# and passed in as parameters 4/5; the script HEAD-verifies that URL and falls
# back to scraping Splunk's download page if it 404s. Installs older than the
# target are upgraded in place. Per-fix history is in git, not this header.
#
# Prerequisites:
#   - PPPC profile for Full Disk Access deployed via MDM
#   - SplunkCloudCredentials-Example.pkg installed (by this policy's package step)
#
# Splunk Cloud: https://example.splunkcloud.com/
###############################################################################

SPLUNK_HOME="/opt/splunkforwarder"
CREDENTIALS_FILE="/Library/Application Support/Example/splunkclouduf.spl"
CREDENTIALS_APP="$SPLUNK_HOME/etc/apps/100_example_splunkcloud"
LOG_FILE="/var/log/example_splunk_install.log"
SPLUNK_PASS_FILE="/etc/example_splunk_admin_pass"

# Target version + download URL are passed by the Jamf policy as script
# parameters $4 and $5, sourced from the Terraform locals splunk_target_version
# / splunk_target_url — the single source of truth, shared with the EA-driven
# "Needs Upgrade" smart group. The hardcoded defaults keep the script working if
# it is ever run outside a policy (manual test). To roll the fleet to a new
# version, bump the locals in scripts.tf; keep these defaults roughly in step.
TARGET_VERSION="${4:-10.4.0}"
TARGET_URL="${5:-https://download.splunk.com/products/universalforwarder/releases/10.4.0/osx/splunkforwarder-10.4.0-f798d4d49089-darwin-arm64.tgz}"

# Splunk download page used only as a fallback if the pinned URL ever 404s.
SPLUNK_DOWNLOAD_PAGE="https://www.splunk.com/en_us/download/universal-forwarder.html"

# Populated by resolve_download(): the verified URL/version we will install.
RESOLVED_URL=""
RESOLVED_VERSION=""

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# ============================================
# Last-run status reporting for the "Splunk UF Status" EA
# Writes STATE|timestamp|reason on exit so the daily compliance check can read
# the real install/upgrade outcome from inventory instead of only Jamf's Failed
# flag. A FAIL status drives the "Splunk UF - Needs Remediation" smart group,
# which an Ongoing remediation policy re-runs until the device reports OK —
# escaping the "Once per computer + exit 1 = permanently Failed" trap.
# ============================================
STATUS_DIR="/Library/Application Support/Example/jamf-status"
STATUS_FILE="$STATUS_DIR/splunk-uf.status"
on_exit() {
    local rc=$?
    mkdir -p "$STATUS_DIR" 2>/dev/null || return 0
    local ts
    ts=$(date '+%Y-%m-%dT%H:%M:%S')
    if [[ $rc -eq 0 ]]; then
        printf 'OK|%s|\n' "$ts" > "$STATUS_FILE" 2>/dev/null || true
    else
        local reason
        reason=$(grep -iE 'ERROR|FATAL' "$LOG_FILE" 2>/dev/null | tail -1 | cut -c1-200)
        printf 'FAIL|%s|%s\n' "$ts" "${reason:-exit $rc}" > "$STATUS_FILE" 2>/dev/null || true
    fi
}
trap on_exit EXIT

# ============================================
# FIX 6: Early credential-file check
# The Jamf policy installs SplunkCloudCredentials-Example.pkg BEFORE
# running this script. If the .spl file is missing, the package step failed
# (distribution point unreachable, management account null, etc.).
# Diagnose immediately rather than burning 3 install attempts.
# ============================================
check_credentials_file() {
    # Primary path
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        return 0
    fi

    # Alternate paths used by older/newer package versions
    local alt_paths=(
        "/Library/Application Support/Example/splunk/splunkclouduf.spl"
        "/Library/Application Support/Splunk/splunkclouduf.spl"
        "/tmp/splunkclouduf.spl"
    )
    for alt in "${alt_paths[@]}"; do
        if [[ -f "$alt" ]]; then
            log "Credentials file found at alternate path: $alt"
            log "Updating CREDENTIALS_FILE to match — package may have changed install location"
            CREDENTIALS_FILE="$alt"
            return 0
        fi
    done

    # File is genuinely missing — emit diagnostics
    log "ERROR: SplunkCloud credentials file not found."
    log "Expected: $CREDENTIALS_FILE"
    log "This means the SplunkCloudCredentials-Example.pkg package step in"
    log "this Jamf policy failed to install. Common causes:"
    log "  - Jamf management account is null (device needs re-enrollment or"
    log "    management account repair)"
    log "  - Distribution point is unreachable from this device"
    log "  - Package is missing from the distribution point"
    log ""
    log "Directory diagnostics:"
    local base_dir="/Library/Application Support/Example"
    if [[ -d "$base_dir" ]]; then
        log "  $base_dir exists. Contents:"
        ls -laR "$base_dir" 2>/dev/null | while IFS= read -r line; do log "    $line"; done
    else
        log "  $base_dir does NOT exist — package was not installed at all"
        log "  /Library/Application Support contents (Example/Splunk entries):"
        for entry in "/Library/Application Support/"/*/; do
            [[ -e "$entry" ]] || continue
            name=$(basename "$entry")
            if echo "$name" | grep -qiE "electron|splunk"; then
                log "    $entry"
            fi
        done
    fi

    # FIX 7: Structured diagnostics to pinpoint the package step failure cause
    diagnose_package_failure
    return 1
}

# ============================================
# FIX 7: Package step failure diagnostics
# Called when credentials file is missing. Checks management account, Jamf
# server connectivity, and Splunk Cloud reachability to surface root cause
# directly in the Jamf policy log.
# ============================================
diagnose_package_failure() {
    log "--- Package step failure diagnostics ---"

    # Check Jamf management account — a null/empty account means the distribution
    # point cannot authenticate and package delivery will always fail.
    local mgmt_user
    mgmt_user=$(defaults read /Library/Preferences/com.jamfsoftware.jamf.plist \
        managementUserName 2>/dev/null || echo "")
    if [ -z "$mgmt_user" ]; then
        log "  Jamf management account : NULL"
        log "  >>> This is the most likely cause of the package step failure."
        log "  >>> Resolution: run 'sudo jamf manage' or re-enroll the device."
    else
        log "  Jamf management account : $mgmt_user (present)"
    fi

    # Check Jamf server reachability
    local jamf_url
    jamf_url=$(defaults read /Library/Preferences/com.jamfsoftware.jamf.plist \
        jamf_url 2>/dev/null || echo "")
    if [ -n "$jamf_url" ]; then
        local jamf_http
        jamf_http=$(curl -sL --max-time 10 -o /dev/null \
            -w "%{http_code}" "${jamf_url%/}/healthCheck.html" 2>/dev/null || echo "error")
        log "  Jamf server             : $jamf_url  (HTTP $jamf_http)"
        if [[ "$jamf_http" != 2* ]] && [[ "$jamf_http" != 3* ]]; then
            log "  >>> Jamf server unreachable — device may be off-VPN or firewall-blocked."
        fi
    else
        log "  Jamf server             : URL not found in preferences"
    fi

    # Check Splunk Cloud endpoint reachability
    local splunk_http
    splunk_http=$(curl -sL --max-time 10 -o /dev/null \
        -w "%{http_code}" "https://example.splunkcloud.com" 2>/dev/null || echo "error")
    log "  Splunk Cloud endpoint   : example.splunkcloud.com  (HTTP $splunk_http)"
    if [[ "$splunk_http" == "error" ]] || [[ "$splunk_http" == "000" ]]; then
        log "  >>> Splunk Cloud unreachable — may indicate a proxy/DNS issue."
    fi

    log "--- End diagnostics ---"
}

# ============================================
# FIX 2: Resolve admin password securely
# ============================================
get_admin_password() {
    if [[ -f "$SPLUNK_PASS_FILE" ]]; then
        cat "$SPLUNK_PASS_FILE"
    else
        # Generate and persist a random password on first install
        local PASS
        PASS=$(openssl rand -base64 18 | tr -d '/+=' | head -c 20)
        echo "$PASS" > "$SPLUNK_PASS_FILE"
        chmod 600 "$SPLUNK_PASS_FILE"
        echo "$PASS"
    fi
}

ADMIN_PASSWORD=$(get_admin_password)

# ============================================
# FIX 10: Resolve a real, reachable download URL
# The download filename embeds a per-build hash that cannot be derived from the
# version, so we never synthesise it. We trust the Terraform-pinned URL first
# (HEAD-verified) and only fall back to scraping the live page if it 404s.
# ============================================
validate_download_url() {
    local URL="$1"
    local HTTP_CODE
    HTTP_CODE=$(curl -sL --max-time 15 -o /dev/null -w "%{http_code}" --head "$URL" 2>/dev/null)
    if [[ "$HTTP_CODE" =~ ^2 ]]; then
        return 0
    fi
    log "URL HEAD check returned HTTP $HTTP_CODE for: $URL"
    return 1
}

# Scrape the live download page for the highest-versioned darwin-arm64 build.
# Returns the full URL (with hash) on stdout, or empty if none found.
scrape_latest_arm64_url() {
    curl -sL --max-time 20 "$SPLUNK_DOWNLOAD_PAGE" 2>/dev/null \
        | grep -oE 'https://download\.splunk\.com/products/universalforwarder/releases/[0-9.]+/osx/splunkforwarder-[0-9.]+-[a-f0-9]+-darwin-arm64\.tgz' \
        | sed -E 's#(.*/releases/([0-9.]+)/.*)#\2 \1#' \
        | sort -V \
        | tail -1 \
        | sed -E 's/^[0-9.]+ //'
}

# Sets RESOLVED_URL / RESOLVED_VERSION to a HEAD-verified download. Prefers the
# pinned Terraform URL; scrapes as a last resort. Returns 1 if nothing usable.
resolve_download() {
    if [[ -n "$TARGET_URL" ]] && validate_download_url "$TARGET_URL"; then
        RESOLVED_URL="$TARGET_URL"
        RESOLVED_VERSION="$TARGET_VERSION"
        log "Using pinned Splunk UF ${RESOLVED_VERSION}"
        return 0
    fi

    log "Pinned URL unavailable; scraping ${SPLUNK_DOWNLOAD_PAGE} for latest darwin-arm64 build"
    local scraped
    scraped=$(scrape_latest_arm64_url)
    if [[ -n "$scraped" ]] && validate_download_url "$scraped"; then
        RESOLVED_URL="$scraped"
        RESOLVED_VERSION=$(echo "$scraped" | sed -E 's#.*/releases/([0-9.]+)/.*#\1#')
        log "Resolved Splunk UF ${RESOLVED_VERSION} via scrape"
        return 0
    fi

    log "ERROR: could not resolve a usable Splunk UF download URL (pinned URL 404 and scrape failed)"
    return 1
}

# Read the installed UF version from etc/splunk.version (no daemon needed),
# falling back to `splunk version`. Empty if not installed/unknown.
get_installed_version() {
    local vf="$SPLUNK_HOME/etc/splunk.version"
    if [[ -f "$vf" ]]; then
        grep -E '^VERSION=' "$vf" | head -1 | cut -d= -f2 | tr -d '[:space:]'
    elif [[ -x "$SPLUNK_HOME/bin/splunk" ]]; then
        "$SPLUNK_HOME/bin/splunk" version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
    fi
}

# Return 0 if version $1 is strictly older than $2 (semantic, via sort -V).
version_lt() {
    [[ "$1" != "$2" ]] && \
        [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" == "$1" ]]
}

# ============================================
# Validation Function
# ============================================
validate() {
    local uf_ok=false
    local creds_ok=false
    local running_ok=false
    local version_ok=true

    [ -f "$SPLUNK_HOME/bin/splunk" ] && uf_ok=true
    [ -d "$CREDENTIALS_APP" ] && creds_ok=true
    pgrep -x "splunkd" > /dev/null && running_ok=true

    # FIX 10(b): an installed-but-outdated forwarder is NOT fully configured —
    # fail validation so the attempt loop runs the in-place upgrade. Compared
    # against the Terraform-pinned target (no network needed here).
    if $uf_ok && [[ -n "$TARGET_VERSION" ]]; then
        local cur
        cur=$(get_installed_version)
        if [[ -n "$cur" ]] && version_lt "$cur" "$TARGET_VERSION"; then
            version_ok=false
        fi
    fi

    if $uf_ok && $creds_ok && $running_ok && $version_ok; then
        return 0
    else
        log "Validation: UF=$uf_ok, Credentials=$creds_ok, Running=$running_ok, VersionCurrent=$version_ok"
        return 1
    fi
}

# Download $1 (URL) to /tmp and sanity-check it's a real package rather than an
# error/redirect page. Echoes the downloaded file path on success.
download_package() {
    local url="$1"
    local tgz
    tgz="/tmp/$(basename "$url")"
    # All diagnostics go to stderr; only the final path is written to stdout so
    # the caller's $(download_package ...) capture stays clean.
    log "Downloading ${url}..." >&2
    cd /tmp || { log "ERROR: Cannot cd to /tmp" >&2; return 1; }
    if ! curl -L -o "$tgz" "$url" 2>&1 | tee -a "$LOG_FILE" >&2; then
        log "ERROR: Download failed" >&2
        return 1
    fi
    local filesize
    filesize=$(stat -f%z "$tgz" 2>/dev/null || echo "0")
    if [ "$filesize" -lt 50000000 ]; then
        if [ "$filesize" -lt 10000 ]; then
            log "ERROR: Downloaded file is tiny ($filesize bytes) — likely a network error or redirect page, not the actual package" >&2
        else
            log "ERROR: Downloaded file too small ($filesize bytes) — URL may point to wrong version" >&2
        fi
        rm -f "$tgz"
        return 1
    fi
    log "Downloaded $(basename "$tgz") (${filesize} bytes)" >&2
    echo "$tgz"
}

# ============================================
# FIX 10(b): In-place upgrade of an existing forwarder
# Extracting the new tarball over $SPLUNK_HOME overlays the binaries while
# preserving etc/ (config, credentials app, passwd). Splunk migrates config on
# the next start. Requires RESOLVED_URL/RESOLVED_VERSION (call resolve_download
# first). $1 = currently installed version (for logging).
# ============================================
upgrade_splunk_uf() {
    local cur="$1"
    log "Upgrade available: ${cur:-unknown} -> ${RESOLVED_VERSION}. Performing in-place upgrade."

    local tgz
    tgz=$(download_package "$RESOLVED_URL") || return 1

    log "Stopping splunkd before upgrade..."
    "$SPLUNK_HOME/bin/splunk" stop 2>&1 | tee -a "$LOG_FILE"
    sleep 5

    log "Extracting ${RESOLVED_VERSION} over ${SPLUNK_HOME} (config preserved)..."
    if ! tar xzf "$tgz" -C /opt 2>&1 | tee -a "$LOG_FILE"; then
        log "ERROR: Extraction failed during upgrade"
        rm -f "$tgz"
        # Bring the existing version back up so the device keeps forwarding.
        "$SPLUNK_HOME/bin/splunk" start --answer-yes --no-prompt 2>&1 | tee -a "$LOG_FILE"
        return 1
    fi
    rm -f "$tgz"
    chown -R root:wheel "$SPLUNK_HOME"

    log "Starting upgraded splunkd (accepting license / migration prompts)..."
    "$SPLUNK_HOME/bin/splunk" start --accept-license --answer-yes --no-prompt \
        2>&1 | tee -a "$LOG_FILE"
    sleep 15

    if ! pgrep -x "splunkd" > /dev/null; then
        log "ERROR: splunkd failed to start after upgrade"
        return 1
    fi

    local now
    now=$(get_installed_version)
    if [[ "$now" == "$RESOLVED_VERSION" ]]; then
        log "Upgrade complete — now running ${now}"
    else
        log "WARNING: post-upgrade version is ${now:-unknown}, expected ${RESOLVED_VERSION}"
    fi

    # The launchd boot-start entry can change between major versions; re-assert.
    "$SPLUNK_HOME/bin/splunk" enable boot-start -user root \
        --accept-license --answer-yes --no-prompt 2>&1 | tee -a "$LOG_FILE"
    return 0
}

# ============================================
# Install Splunk UF
# ============================================
install_splunk_uf() {
    if [ -f "$SPLUNK_HOME/bin/splunk" ]; then
        local cur
        cur=$(get_installed_version)
        log "Splunk UF already installed at $SPLUNK_HOME (version ${cur:-unknown})"

        # FIX 10(b): upgrade in place when older than the pinned target.
        if [[ -n "$TARGET_VERSION" && -n "$cur" ]] && version_lt "$cur" "$TARGET_VERSION"; then
            if resolve_download; then
                upgrade_splunk_uf "$cur" || {
                    log "ERROR: Splunk UF upgrade failed; keeping existing ${cur} running"
                    pgrep -x "splunkd" > /dev/null || \
                        "$SPLUNK_HOME/bin/splunk" start --answer-yes --no-prompt 2>&1 | tee -a "$LOG_FILE"
                    return 1
                }
            else
                log "WARNING: upgrade needed (${cur} -> ${TARGET_VERSION}) but no reachable download; staying on ${cur}"
            fi
        fi

        # Even if already installed, ensure splunkd is running
        if ! pgrep -x "splunkd" > /dev/null; then
            log "Splunk binary exists but daemon not running, starting..."
            "$SPLUNK_HOME/bin/splunk" start --answer-yes --no-prompt 2>&1 | tee -a "$LOG_FILE"
            sleep 10
            # Verify it's actually running
            if ! pgrep -x "splunkd" > /dev/null; then
                log "ERROR: Failed to start splunkd"
                return 1
            fi
        fi

        # FIX 8/9: Verify that ADMIN_PASSWORD matches Splunk's current admin credential.
        # When Splunk is pre-installed before MDM enrollment (e.g. user-installed),
        # SPLUNK_PASS_FILE does not exist; get_admin_password() generates a fresh
        # random password that will not match the existing Splunk admin credential.
        # Detect the mismatch and reset via user-seed.conf so that
        # install_credentials() can authenticate successfully on this same run.
        #
        # FIX 9: user-seed.conf is only consulted when etc/passwd does NOT exist.
        # FIX 8 wrote the seed but left passwd intact, so Splunk silently ignored
        # the seed on restart and the password reset never took effect. The fix
        # removes passwd before stopping Splunk so the restart re-initialises
        # credentials from the seed file (Splunk recreates passwd on start).
        if ! "$SPLUNK_HOME/bin/splunk" show splunk-launch-conf \
                -auth "admin:${ADMIN_PASSWORD}" >/dev/null 2>&1; then
            log "FIX 9: Admin password mismatch detected (pre-installed or externally managed Splunk)."
            log "Resetting admin password via user-seed.conf to match $SPLUNK_PASS_FILE..."
            local seed_conf="$SPLUNK_HOME/etc/system/local/user-seed.conf"
            mkdir -p "$(dirname "$seed_conf")"
            printf '[user_info]\nUSERNAME = admin\nPASSWORD = %s\n' "$ADMIN_PASSWORD" > "$seed_conf"
            chmod 600 "$seed_conf"
            # user-seed.conf is only read when etc/passwd does not exist.
            # Remove passwd so the seed takes effect; Splunk recreates it on start.
            local passwd_file="$SPLUNK_HOME/etc/passwd"
            if [[ -f "$passwd_file" ]]; then
                log "Removing $passwd_file so user-seed.conf is applied on restart"
                rm -f "$passwd_file"
            fi
            "$SPLUNK_HOME/bin/splunk" stop 2>&1 | tee -a "$LOG_FILE"
            sleep 5
            "$SPLUNK_HOME/bin/splunk" start --accept-license --answer-yes --no-prompt \
                2>&1 | tee -a "$LOG_FILE"
            sleep 15
            rm -f "$seed_conf"
            if ! pgrep -x "splunkd" > /dev/null; then
                log "ERROR: splunkd failed to start after password reset"
                return 1
            fi
            log "Admin password reset successfully — proceeding with credentials install"
        fi

        return 0
    fi

    # FIX 10(a): resolve a real, HEAD-verified download URL (pinned, else scrape).
    if ! resolve_download; then
        log "ERROR: Cannot install — no reachable Splunk UF download URL"
        return 1
    fi
    log "Installing fresh Splunk UF ${RESOLVED_VERSION}"

    local SPLUNK_TGZ
    SPLUNK_TGZ=$(download_package "$RESOLVED_URL") || return 1

    log "Extracting..."
    mkdir -p /opt
    tar xzf "${SPLUNK_TGZ}" -C /opt 2>&1 | tee -a "$LOG_FILE"
    rm -f "${SPLUNK_TGZ}"

    if [ ! -f "$SPLUNK_HOME/bin/splunk" ]; then
        log "ERROR: Extraction failed — splunk binary not found after extract"
        return 1
    fi

    log "Starting Splunk first time..."
    "$SPLUNK_HOME/bin/splunk" start --accept-license --answer-yes --no-prompt \
        --seed-passwd "$ADMIN_PASSWORD" 2>&1 | tee -a "$LOG_FILE"

    # FIX 4: Explicit verification that splunkd is responsive
    sleep 15

    local splunkd_attempts=0
    while [ $splunkd_attempts -lt 5 ]; do
        if pgrep -x "splunkd" > /dev/null 2>&1; then
            log "Confirmed splunkd is running (attempt $((splunkd_attempts+1)))"
            break
        fi
        log "Waiting for splunkd to start... (attempt $((splunkd_attempts+1)))"
        sleep 3
        splunkd_attempts=$((splunkd_attempts+1))
    done

    if ! pgrep -x "splunkd" > /dev/null; then
        log "ERROR: splunkd failed to start after installation"
        return 1
    fi

    chown -R root:wheel "$SPLUNK_HOME"

    "$SPLUNK_HOME/bin/splunk" enable boot-start -user root \
        --accept-license --answer-yes --no-prompt 2>&1 | tee -a "$LOG_FILE"

    log "Splunk UF installed successfully with running daemon"
    return 0
}

# ============================================
# Install Credentials
# ============================================
install_credentials() {
    if [ -d "$CREDENTIALS_APP" ]; then
        log "Credentials already installed"
        return 0
    fi

    # Ensure credentials file exists (FIX 6: already checked at top, but re-check here)
    if ! check_credentials_file; then
        return 1
    fi

    # Ensure Splunk is running
    if ! pgrep -x "splunkd" > /dev/null; then
        log "Starting Splunk..."
        "$SPLUNK_HOME/bin/splunk" start 2>&1 | tee -a "$LOG_FILE"
        sleep 10
    fi

    log "Installing credentials from: $CREDENTIALS_FILE"
    if "$SPLUNK_HOME/bin/splunk" install app "$CREDENTIALS_FILE" \
        -auth admin:"$ADMIN_PASSWORD" 2>&1 | tee -a "$LOG_FILE"; then
        log "Credentials installed, restarting..."
        "$SPLUNK_HOME/bin/splunk" restart 2>&1 | tee -a "$LOG_FILE"
        sleep 10
        return 0
    else
        log "ERROR: Credentials install failed"
        return 1
    fi
}

# ============================================
# Main
# ============================================
log "=========================================="
log "Splunk UF Installation & Configuration"
log "=========================================="

# Check if already fully configured
if validate; then
    log "SUCCESS: Already fully configured"
    exit 0
fi

# FIX 6: Check credentials file BEFORE attempting any install work.
# If the package step failed, there's no point trying — fail fast with
# actionable diagnostics rather than burning 3 full install attempts.
#
# FIX 10(b): skip this gate when credentials are ALREADY installed
# ($CREDENTIALS_APP present). The "Splunk UF - Upgrade" policy is script-only
# (no package payload), so the source .spl may be absent on an already-
# configured device — but it doesn't need it: install_credentials() short-
# circuits on the existing app and install_splunk_uf() performs the upgrade.
if [ ! -d "$CREDENTIALS_APP" ] && ! check_credentials_file; then
    log "FATAL: Cannot proceed without credentials file — see diagnostics above"
    log "Fix: ensure the SplunkCloudCredentials-Example package step in this"
    log "policy succeeds, then flush MDM receipts and retry."
    exit 1 # jamf-ci: exit1-intentional
fi

# Try up to 3 times
for attempt in 1 2 3; do
    log "Attempt $attempt of 3"

    install_splunk_uf || { log "Splunk UF install step failed on attempt $attempt"; sleep 5; continue; }
    install_credentials || { log "Credentials install step failed on attempt $attempt"; sleep 5; continue; }

    # Ensure running
    if ! pgrep -x "splunkd" > /dev/null; then
        "$SPLUNK_HOME/bin/splunk" start 2>&1 | tee -a "$LOG_FILE"
        sleep 10
    fi

    if validate; then
        log "=========================================="
        log "SUCCESS: Splunk UF installed and configured"
        log "=========================================="
        exit 0
    fi

    log "Attempt $attempt failed, retrying..."
    sleep 5
done

log "ERROR: Failed after 3 attempts -- check $LOG_FILE for details"
exit 1 # jamf-ci: exit1-intentional
