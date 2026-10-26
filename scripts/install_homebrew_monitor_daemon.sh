#!/bin/bash
# Install Homebrew Monitor Daemon
# Deploys a LaunchDaemon that continuously monitors for unauthorized Homebrew installations
# Deletes any Homebrew found for non-service accounts (srv_*)

SCRIPT_PATH="/usr/local/bin/block_user_homebrew.sh"
PLIST_PATH="/Library/LaunchDaemons/com.example.blockhomebrew.plist"
LOGFILE="/var/log/block_homebrew.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOGFILE"
}

# Create the monitoring script
cat > "$SCRIPT_PATH" << 'SCRIPT'
#!/bin/bash
# Homebrew Monitor Daemon Script
# Continuously scans for and DELETES unauthorized Homebrew installations

LOGFILE="/var/log/block_homebrew.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOGFILE"
}

# Rotate log if it exceeds 10 MB to prevent unbounded growth and launchd throttling
rotate_log() {
    local max_size=$((10 * 1024 * 1024))
    if [[ -f "$LOGFILE" ]]; then
        local size
        size=$(stat -f%z "$LOGFILE" 2>/dev/null || echo 0)
        if (( size > max_size )); then
            tail -n 500 "$LOGFILE" > "${LOGFILE}.tmp" && mv "${LOGFILE}.tmp" "$LOGFILE"
            log_message "Log rotated (was ${size} bytes, kept last 500 lines)"
        fi
    fi
}

is_service_account() {
    local user="$1"
    [[ "$user" == srv_* || "$user" == "Shared" ]]
}

delete_homebrew() {
    local brew_dir="$1"
    local owner="$2"

    if [[ -d "$brew_dir" ]]; then
        log_message "DELETING: $brew_dir (owner: $owner)"
        rm -rf "$brew_dir" 2>/dev/null

        if [[ ! -d "$brew_dir" ]]; then
            log_message "DELETED: $brew_dir successfully removed"
            logger -t "BlockHomebrew" "Deleted Homebrew installation at $brew_dir (owner: $owner)"
            return 0
        else
            log_message "ERROR: Failed to delete $brew_dir"
            return 1
        fi
    fi
    return 1
}

scan_for_homebrew() {
    local deleted_count=0

    for user_home in /Users/*/; do
        username=$(basename "$user_home")
        is_service_account "$username" && continue

        # Check common Homebrew directory locations
        for brew_dir in "${user_home}homebrew" "${user_home}.homebrew" "${user_home}opt/homebrew" "${user_home}.local/homebrew"; do
            if [[ -d "$brew_dir" ]]; then
                log_message "FOUND: Homebrew directory at $brew_dir (owner: $username)"
                if delete_homebrew "$brew_dir" "$username"; then
                    ((deleted_count++))
                fi
            fi
        done

        # Also check for brew binary anywhere in user home and remove parent homebrew directory
        while IFS= read -r -d '' brew_path; do
            brew_dir=$(dirname "$(dirname "$brew_path")")
            if [[ -d "$brew_dir" && "$brew_dir" == *"homebrew"* ]]; then
                log_message "FOUND: Homebrew binary at $brew_path (owner: $username)"
                if delete_homebrew "$brew_dir" "$username"; then
                    ((deleted_count++))
                fi
            fi
        done < <(find "$user_home" -maxdepth 5 -name "brew" -type f -print0 2>/dev/null)

        # Clean up Homebrew cache and other remnants
        for cache_dir in "${user_home}Library/Caches/Homebrew" "${user_home}.cache/Homebrew"; do
            if [[ -d "$cache_dir" ]]; then
                log_message "DELETING CACHE: $cache_dir"
                rm -rf "$cache_dir" 2>/dev/null
            fi
        done

        # Remove Homebrew environment from shell profiles
        for profile in "${user_home}.zshrc" "${user_home}.bash_profile" "${user_home}.bashrc" "${user_home}.profile"; do
            if [[ -f "$profile" ]] && grep -q "homebrew" "$profile" 2>/dev/null; then
                log_message "CLEANING: Removing Homebrew references from $profile"
                sed -i '' '/homebrew/d' "$profile" 2>/dev/null
                sed -i '' '/HOMEBREW/d' "$profile" 2>/dev/null
            fi
        done
    done

    [[ $deleted_count -gt 0 ]] && log_message "Deleted $deleted_count Homebrew installation(s) this cycle"
}

log_message "Homebrew monitor daemon started (DELETE mode)"

while true; do
    rotate_log
    scan_for_homebrew
    sleep 60
done
SCRIPT

chmod +x "$SCRIPT_PATH"

# Create the LaunchDaemon plist
cat > "$PLIST_PATH" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.example.blockhomebrew</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/usr/local/bin/block_user_homebrew.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/block_homebrew.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/block_homebrew.log</string>
    <key>ThrottleInterval</key>
    <integer>10</integer>
</dict>
</plist>
PLIST

# Set correct permissions
chown root:wheel "$PLIST_PATH"
chmod 644 "$PLIST_PATH"

# ─────────────────────────────────────────────────────────────────────────────
# FIX (2026-05-02 — persistent bootstrap failures on M4 devices):
#
# Two compounding issues caused `launchctl bootstrap` to fail even with the
# existing 3-attempt retry loop:
#
# 1. Path-based bootout (`launchctl bootout system /path/to.plist`) silently
#    fails on macOS 15 when launchd has already discarded its internal plist-
#    path reference after a rapid crash/restart cycle. The label remains
#    registered, so the subsequent bootstrap fails with "label already exists"
#    despite the apparent bootout success.
#
# 2. Rapid-crash throttling: when the daemon crashes repeatedly, launchd marks
#    it as 'disabled' in its service database. A subsequent `bootstrap` returns
#    exit 0 but never actually spawns the process, leaving the smart-group
#    criterion unsatisfied and the policy re-triggering on every Jamf check-in.
#
# Fixes:
#   - Idempotency guard: if daemon is already running, exit 0 immediately
#     (handles brief race between smart-group evaluation and policy dispatch)
#   - Label-based bootout: `launchctl bootout system/<label>` directly
#     addresses the registered service regardless of plist path reference state
#   - `launchctl enable system/<label>` before the bootstrap loop clears any
#     'disabled' flag written by launchd's throttle mechanism
#   - Capture full stderr from each bootstrap attempt and print to policy log
#     so future failures show the exact launchd error message
#   - Retry sleep 5s → 10s to match M4 process-teardown latency fix from PR #49
#   - Emit macOS version + CPU brand in failure summary for cross-device triage
# ─────────────────────────────────────────────────────────────────────────────
_DAEMON_LABEL="com.example.blockhomebrew"

# Idempotency check: nothing to do if the daemon is already running
if launchctl print "system/${_DAEMON_LABEL}" 2>/dev/null | grep -q "state = running"; then
    echo "Daemon ${_DAEMON_LABEL} is already loaded and running — nothing to do."
    log_message "Homebrew monitor daemon already running — skipped reinstall"
    exit 0
fi

# Label-based bootout (more reliable than path-based on macOS 15)
launchctl bootout "system/${_DAEMON_LABEL}" 2>/dev/null || true
sleep 2

# Clear any 'disabled' flag so bootstrap actually starts the process
launchctl enable "system/${_DAEMON_LABEL}" 2>/dev/null || true

_BOOTSTRAP_OK=false
for _attempt in 1 2 3; do
    _BOOTSTRAP_ERR=$(launchctl bootstrap system "$PLIST_PATH" 2>&1)
    _BOOTSTRAP_EXIT=$?
    if [ $_BOOTSTRAP_EXIT -eq 0 ]; then
        _BOOTSTRAP_OK=true
        echo "launchctl bootstrap succeeded on attempt ${_attempt}."
        break
    fi
    echo "launchctl bootstrap attempt ${_attempt} failed (exit ${_BOOTSTRAP_EXIT}):"
    echo "  ${_BOOTSTRAP_ERR}"
    echo "Retrying in 10s..."
    launchctl bootout "system/${_DAEMON_LABEL}" 2>/dev/null || true
    sleep 10
done

if ! $_BOOTSTRAP_OK; then
    echo "ERROR: launchctl bootstrap failed after 3 attempts"
    echo "  Plist path   : $PLIST_PATH"
    echo "  Daemon label : ${_DAEMON_LABEL}"
    echo "  macOS version: $(sw_vers -productVersion 2>/dev/null || echo unknown)"
    echo "  CPU          : $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)"
    exit 1 # jamf-ci: exit1-intentional
fi

log_message "Homebrew monitor daemon installed and started (DELETE mode)"

exit 0
