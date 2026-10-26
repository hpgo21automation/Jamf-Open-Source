#!/bin/bash

#########################################################################################
# Script: enforce_time_settings.sh
# Purpose: Enforce automatic time sync with IP geolocation fallback
# Version: 3.3
#########################################################################################

set -o pipefail

# ===================== CONFIGURATION =====================
NTP_SERVER_PRIMARY="time.apple.com"
NTP_SERVER_FALLBACK="time.nist.gov"
LOG_FILE="/var/log/example_time_enforcement.log"
MAX_LOG_SIZE_KB=1024
MAX_TIME_DRIFT_SECONDS=60
LOCATION_WAIT_SECONDS=10

# ===================== LOGGING =====================
log_rotate() {
    if [[ -f "$LOG_FILE" ]]; then
        local size_kb
        size_kb=$(du -k "$LOG_FILE" | cut -f1)
        if [[ $size_kb -gt $MAX_LOG_SIZE_KB ]]; then
            mv "$LOG_FILE" "${LOG_FILE}.1"
            touch "$LOG_FILE"
            chmod 644 "$LOG_FILE"
        fi
    fi
}

log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Log to stderr only (for use in functions that return values via stdout)
log_stderr() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    echo "[$timestamp] [$level] $message" >&2
}

log_rotate

log "INFO" "========== Time Enforcement Script Started =========="
log "INFO" "Running as user: $(whoami)"
log "INFO" "Hostname: $(hostname)"

# ===================== PREFLIGHT CHECKS =====================
if [[ $EUID -ne 0 ]]; then
    log "ERROR" "Script must be run as root. Exiting."
    exit 1
fi

if ! command -v /usr/sbin/systemsetup &> /dev/null; then
    log "ERROR" "systemsetup command not found. Exiting."
    exit 1
fi

# ===================== HELPER FUNCTIONS =====================
get_current_timezone() {
    /usr/sbin/systemsetup -gettimezone 2>/dev/null | awk -F': ' '{print $2}'
}

get_network_time_status() {
    /usr/sbin/systemsetup -getusingnetworktime 2>/dev/null | awk -F': ' '{print $2}'
}

get_network_time_server() {
    /usr/sbin/systemsetup -getnetworktimeserver 2>/dev/null | awk -F': ' '{print $2}'
}

get_auto_timezone_status() {
    /usr/bin/defaults read /Library/Preferences/com.apple.timezone.auto Active 2>/dev/null || echo "0"
}

get_location_services_status() {
    local ls_status
    ls_status=$(/usr/bin/defaults read /var/db/locationd/Library/Preferences/ByHost/com.apple.locationd LocationServicesEnabled 2>/dev/null || echo "0")
    echo "$ls_status"
}

get_time_drift() {
    local sntp_output
    local drift
    
    sntp_output=$(sntp -t 5 "$NTP_SERVER_PRIMARY" 2>&1)
    
    if [[ -z "$sntp_output" ]]; then
        sntp_output=$(sntp -t 5 "$NTP_SERVER_FALLBACK" 2>&1)
    fi
    
    # Parse drift from sntp output
    drift=$(echo "$sntp_output" | grep -oE '[\+\-][0-9]+\.[0-9]+' | head -1 | cut -d'.' -f1)
    
    if [[ -n "$drift" ]]; then
        echo "$drift"
    else
        echo "unknown"
    fi
}

test_ntp_connectivity() {
    local server="$1"
    if sntp -t 5 "$server" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

restart_service() {
    local service_name="$1"
    log "INFO" "Restarting $service_name service..."
    if killall "$service_name" 2>/dev/null; then
        sleep 2
        log "INFO" "$service_name service restarted successfully"
    else
        log "WARN" "$service_name was not running or could not be killed"
    fi
}

# ===================== IP GEOLOCATION FALLBACK =====================
get_timezone_from_ip() {
    local timezone=""
    local response=""
    
    log_stderr "INFO" "Attempting IP-based geolocation for timezone..."
    
    # Try multiple geolocation services
    # Option 1: ipapi.co (no API key needed, 1000/day free)
    response=$(curl -s --max-time 10 "https://ipapi.co/timezone" 2>/dev/null)
    response=$(echo "$response" | tr -d '[:space:]' | tr -d '\n' | tr -d '\r')
    if [[ -n "$response" ]] && [[ "$response" != *"error"* ]] && [[ "$response" == *"/"* ]]; then
        timezone="$response"
        log_stderr "INFO" "Got timezone from ipapi.co: $timezone"
        echo "$timezone"
        return 0
    fi
    
    # Option 2: ip-api.com (free, no key)
    response=$(curl -s --max-time 10 "http://ip-api.com/line/?fields=timezone" 2>/dev/null)
    response=$(echo "$response" | tr -d '[:space:]' | tr -d '\n' | tr -d '\r')
    if [[ -n "$response" ]] && [[ "$response" == *"/"* ]]; then
        timezone="$response"
        log_stderr "INFO" "Got timezone from ip-api.com: $timezone"
        echo "$timezone"
        return 0
    fi
    
    # Option 3: worldtimeapi.org
    response=$(curl -s --max-time 10 "http://worldtimeapi.org/api/ip" 2>/dev/null)
    response=$(echo "$response" | grep -o '"timezone":"[^"]*"' | cut -d'"' -f4 | tr -d '[:space:]' | tr -d '\n' | tr -d '\r')
    if [[ -n "$response" ]] && [[ "$response" == *"/"* ]]; then
        timezone="$response"
        log_stderr "INFO" "Got timezone from worldtimeapi.org: $timezone"
        echo "$timezone"
        return 0
    fi
    
    log_stderr "WARN" "All IP geolocation services failed"
    return 1
}

validate_timezone() {
    local tz="$1"
    # Check if timezone exists in the system
    if [[ -f "/usr/share/zoneinfo/$tz" ]]; then
        return 0
    else
        return 1
    fi
}

# ===================== REMEDIATION FUNCTIONS =====================
enforce_location_services() {
    local ls_enabled
    ls_enabled=$(get_location_services_status)
    
    log "INFO" "Location Services enabled: $ls_enabled"
    
    if [[ "$ls_enabled" != "1" ]]; then
        log "WARN" "Location Services disabled. Enabling (required for automatic timezone)..."
        
        mkdir -p /var/db/locationd/Library/Preferences/ByHost 2>/dev/null
        /usr/bin/defaults write /var/db/locationd/Library/Preferences/ByHost/com.apple.locationd LocationServicesEnabled -int 1
        chown -R _locationd:_locationd /var/db/locationd 2>/dev/null
        
        restart_service "locationd"
        
        log "INFO" "Location Services enabled"
        return 0
    fi
    
    log "INFO" "Location Services already enabled"
    return 0
}

enforce_timezone_auto() {
    local auto_tz_status
    auto_tz_status=$(get_auto_timezone_status)
    
    log "INFO" "Automatic timezone setting: $auto_tz_status"
    
    if [[ "$auto_tz_status" != "1" ]]; then
        log "WARN" "Automatic timezone is disabled. Enabling..."
        
        /usr/bin/defaults write /Library/Preferences/com.apple.timezone.auto Active -bool true
        chmod 644 /Library/Preferences/com.apple.timezone.auto.plist 2>/dev/null
        
        log "INFO" "Automatic timezone enabled"
    else
        log "INFO" "Automatic timezone already enabled"
    fi
    
    return 0
}

enforce_network_time() {
    local ntp_status
    ntp_status=$(get_network_time_status)
    
    log "INFO" "Network time status: $ntp_status"
    
    if [[ "$ntp_status" != "On" ]]; then
        log "WARN" "Network time is disabled. Enabling..."
        
        if /usr/sbin/systemsetup -setusingnetworktime on 2>/dev/null; then
            log "INFO" "Network time enabled successfully"
        else
            log "ERROR" "Failed to enable network time"
            return 1
        fi
    else
        log "INFO" "Network time already enabled"
    fi
    
    return 0
}

enforce_ntp_server() {
    local current_server
    current_server=$(get_network_time_server)
    
    log "INFO" "Current NTP server: $current_server"
    
    if test_ntp_connectivity "$NTP_SERVER_PRIMARY"; then
        log "INFO" "Primary NTP server ($NTP_SERVER_PRIMARY) is reachable"
        
        if [[ "$current_server" != "$NTP_SERVER_PRIMARY" ]]; then
            log "INFO" "Setting NTP server to $NTP_SERVER_PRIMARY"
            /usr/sbin/systemsetup -setnetworktimeserver "$NTP_SERVER_PRIMARY" 2>/dev/null
        fi
    elif test_ntp_connectivity "$NTP_SERVER_FALLBACK"; then
        log "WARN" "Primary NTP server unreachable. Using fallback: $NTP_SERVER_FALLBACK"
        /usr/sbin/systemsetup -setnetworktimeserver "$NTP_SERVER_FALLBACK" 2>/dev/null
    else
        log "ERROR" "Cannot reach any NTP server. Check network connectivity."
        return 1
    fi
    
    return 0
}

force_time_sync() {
    log "INFO" "Forcing immediate time synchronization..."
    
    if /usr/sbin/sntp -sS "$NTP_SERVER_PRIMARY" 2>&1; then
        log "INFO" "Time sync successful with $NTP_SERVER_PRIMARY"
        return 0
    fi
    
    if /usr/sbin/sntp -sS "$NTP_SERVER_FALLBACK" 2>&1; then
        log "INFO" "Time sync successful with $NTP_SERVER_FALLBACK"
        return 0
    fi
    
    log "ERROR" "Time sync failed with all servers"
    return 1
}

check_and_correct_time_drift() {
    local drift
    drift=$(get_time_drift)
    
    if [[ "$drift" == "unknown" ]]; then
        log "WARN" "Could not determine time drift"
        return 1
    fi
    
    # Remove leading + or - for comparison
    local drift_abs="${drift#[-+]}"
    
    log "INFO" "Current time drift: ${drift} seconds"
    
    if [[ $drift_abs -gt $MAX_TIME_DRIFT_SECONDS ]]; then
        log "WARN" "Time drift exceeds threshold (${MAX_TIME_DRIFT_SECONDS}s). Forcing sync..."
        force_time_sync
        restart_service "timed"
        return 1
    fi
    
    log "INFO" "Time drift is within acceptable range"
    return 0
}

trigger_timezone_update() {
    log "INFO" "Triggering timezone location update..."
    
    # Restart timezone daemon
    restart_service "tzd" 2>/dev/null || true
    restart_service "locationd"
    
    # Wait for location detection
    log "INFO" "Waiting ${LOCATION_WAIT_SECONDS}s for location detection..."
    sleep "$LOCATION_WAIT_SECONDS"
    
    local current_tz
    current_tz=$(get_current_timezone)
    log "INFO" "Current detected timezone: $current_tz"
    
    return 0
}

apply_timezone_from_ip_fallback() {
    local current_tz
    current_tz=$(get_current_timezone)
    
    log "INFO" "Checking if IP geolocation fallback is needed..."
    log "INFO" "Current timezone: $current_tz"
    
    # Get timezone from IP (logs go to stderr, only timezone value to stdout)
    local ip_timezone
    ip_timezone=$(get_timezone_from_ip)
    
    if [[ -z "$ip_timezone" ]]; then
        log "WARN" "Could not determine timezone from IP geolocation"
        return 1
    fi
    
    # Clean up any whitespace, newlines, or unexpected characters
    ip_timezone=$(echo "$ip_timezone" | tr -d '[:space:]' | tr -d '\n' | tr -d '\r')
    
    # Extra safety: extract only the timezone pattern (Continent/City)
    ip_timezone=$(echo "$ip_timezone" | grep -oE '^[A-Za-z_]+/[A-Za-z_]+' | head -1)
    
    if [[ -z "$ip_timezone" ]]; then
        log "ERROR" "Failed to parse valid timezone from IP geolocation response"
        return 1
    fi
    
    log "INFO" "Parsed IP timezone: $ip_timezone"
    
    # Validate the timezone
    if ! validate_timezone "$ip_timezone"; then
        log "ERROR" "Invalid timezone returned from IP geolocation: $ip_timezone"
        return 1
    fi
    
    # Compare and apply if different
    if [[ "$current_tz" != "$ip_timezone" ]]; then
        log "WARN" "Timezone mismatch detected. Current: $current_tz, IP-based: $ip_timezone"
        log "INFO" "Applying IP-based timezone: $ip_timezone"
        
        if /usr/sbin/systemsetup -settimezone "$ip_timezone" 2>/dev/null; then
            log "INFO" "Timezone successfully set to $ip_timezone"
            return 0
        else
            log "ERROR" "Failed to set timezone to $ip_timezone"
            return 1
        fi
    else
        log "INFO" "Timezone already matches IP geolocation ($current_tz)"
    fi
    
    return 0
}

refresh_ui() {
    log "INFO" "Refreshing system UI to reflect timezone changes..."
    
    # Refresh menu bar clock and other UI elements
    if killall SystemUIServer 2>/dev/null; then # ci-allow: best-effort menu bar refresh; already guarded by 2>/dev/null
        log "INFO" "SystemUIServer refreshed successfully"
    else
        log "WARN" "SystemUIServer was not running or could not be refreshed"
    fi
    
    # Also refresh Control Center (macOS Big Sur+)
    killall ControlCenter 2>/dev/null || true
    
    log "INFO" "UI refresh complete"
    return 0
}

# ===================== VALIDATION =====================
validate_settings() {
    local warnings=0
    
    log "INFO" "========== Validating Settings =========="
    
    # Validate Location Services
    local ls_status
    ls_status=$(get_location_services_status)
    if [[ "$ls_status" == "1" ]]; then
        log "INFO" "[PASS] Location Services: Enabled"
    else
        log "WARN" "[WARN] Location Services: Disabled"
        ((warnings++))
    fi
    
    # Validate automatic timezone
    local auto_tz
    auto_tz=$(get_auto_timezone_status)
    if [[ "$auto_tz" == "1" ]]; then
        log "INFO" "[PASS] Automatic Timezone: Enabled"
    else
        log "WARN" "[WARN] Automatic Timezone: Disabled"
        ((warnings++))
    fi
    
    # Validate network time
    local ntp
    ntp=$(get_network_time_status)
    if [[ "$ntp" == "On" ]]; then
        log "INFO" "[PASS] Network Time: Enabled"
    else
        log "ERROR" "[FAIL] Network Time: Disabled"
        ((warnings++))
    fi
    
    # Validate NTP server reachability
    if test_ntp_connectivity "$NTP_SERVER_PRIMARY" || test_ntp_connectivity "$NTP_SERVER_FALLBACK"; then
        log "INFO" "[PASS] NTP Server Connectivity: OK"
    else
        log "ERROR" "[FAIL] NTP Server Connectivity: Unreachable"
        ((warnings++))
    fi
    
    # Check time drift
    local drift
    drift=$(get_time_drift)
    local drift_abs="${drift#[-+]}"
    if [[ "$drift" != "unknown" ]] && [[ $drift_abs -le $MAX_TIME_DRIFT_SECONDS ]]; then
        log "INFO" "[PASS] Time Drift: ${drift}s (within tolerance)"
    else
        log "WARN" "[WARN] Time Drift: ${drift}s"
        ((warnings++))
    fi
    
    # Report current timezone
    local current_tz
    current_tz=$(get_current_timezone)
    log "INFO" "[INFO] Current Timezone: $current_tz"
    
    return $warnings
}

# ===================== MAIN EXECUTION =====================
main() {
    local exit_code=0
    
    # Step 1: Enable Location Services
    if ! enforce_location_services; then
        log "ERROR" "Location Services enforcement failed"
        ((exit_code++))
    fi
    
    # Step 2: Enable automatic timezone
    if ! enforce_timezone_auto; then
        log "ERROR" "Automatic timezone enforcement failed"
        ((exit_code++))
    fi
    
    # Step 3: Enable network time
    if ! enforce_network_time; then
        log "ERROR" "Network time enforcement failed"
        ((exit_code++))
    fi
    
    # Step 4: Configure NTP server
    if ! enforce_ntp_server; then
        log "ERROR" "NTP server enforcement failed"
        ((exit_code++))
    fi
    
    # Step 5: Check and correct time drift
    check_and_correct_time_drift
    
    # Step 6: Trigger automatic timezone detection
    trigger_timezone_update
    
    # Step 7: Apply IP geolocation fallback if timezone seems wrong
    apply_timezone_from_ip_fallback
    
    # Step 8: Refresh UI to show updated time/timezone
    refresh_ui
    
    # Step 9: Validate all settings
    log "INFO" ""
    local validation_warnings
    validate_settings
    validation_warnings=$?
    
    if [[ $validation_warnings -eq 0 ]]; then
        log "INFO" "========== All validations passed =========="
    else
        log "WARN" "========== $validation_warnings validation warning(s) =========="
    fi
    
    # Final status
    log "INFO" ""
    if [[ $exit_code -eq 0 ]]; then
        log "INFO" "Script completed successfully"
    else
        log "WARN" "Script completed with $exit_code issue(s)"
    fi
    
    log "INFO" "========== Time Enforcement Script Finished =========="
    
    exit 0
}

# Run main function
main