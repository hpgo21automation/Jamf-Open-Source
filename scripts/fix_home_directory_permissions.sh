#!/bin/bash

###############################################################################
# Fix Home Directory Permissions
# 
# Description: This script identifies the currently logged-in user and ensures
#              they own all files and folders within their home directory.
#              Designed for Jamf Pro Self Service deployment.
#
# Usage: Deploy via Jamf Pro Self Service policy
#
# Author: Example IT
# Version: 1.0
###############################################################################

# Do not use set -e — chown/find on a large home directory will encounter
# permission-denied errors on protected files and exit non-zero, causing Jamf
# to record "Item Failed" even when the script completes successfully.

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
    /usr/bin/logger -t "FixHomePermissions" "$1"
}

# Get the currently logged-in user (excluding root and system accounts)
get_current_user() {
    local currentUser
    currentUser=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk '/Name :/ && ! /loginwindow/ { print $3 }')
    
    if [[ -z "$currentUser" ]] || [[ "$currentUser" == "root" ]] || [[ "$currentUser" == "loginwindow" ]]; then
        log "ERROR: No valid user logged in or running as root"
        exit 1
    fi
    
    echo "$currentUser"
}

# Validate user exists
validate_user() {
    local user="$1"
    if ! /usr/bin/id "$user" &>/dev/null; then
        log "ERROR: User '$user' does not exist"
        exit 1
    fi
}

# Get user's home directory
get_home_directory() {
    local user="$1"
    local homeDir
    homeDir=$(/usr/bin/dscl . -read "/Users/$user" NFSHomeDirectory | /usr/bin/awk '{print $2}')
    
    if [[ -z "$homeDir" ]] || [[ ! -d "$homeDir" ]]; then
        log "ERROR: Home directory for '$user' not found or doesn't exist"
        exit 1
    fi
    
    echo "$homeDir"
}

# Get user's primary group
get_user_group() {
    local user="$1"
    local primaryGroupID
    local groupName
    
    primaryGroupID=$(/usr/bin/id -g "$user")
    groupName=$(/usr/bin/dscl . -search /Groups PrimaryGroupID "$primaryGroupID" | /usr/bin/awk 'NR==1{print $1}')
    
    # Default to "staff" if group lookup fails
    if [[ -z "$groupName" ]]; then
        groupName="staff"
    fi
    
    echo "$groupName"
}

# Fix permissions on home directory
fix_permissions() {
    local user="$1"
    local homeDir="$2"
    local group="$3"
    
    log "Starting permission fix for user: $user"
    log "Home directory: $homeDir"
    log "Primary group: $group"
    
    # Count files before (for reporting)
    local totalItems
    totalItems=$(/usr/bin/find "$homeDir" 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')
    log "Total items in home directory: $totalItems"
    
    # Find items not owned by the user
    local wrongOwner
    wrongOwner=$(/usr/bin/find "$homeDir" ! -user "$user" 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')
    log "Items with incorrect owner: $wrongOwner"
    
    # Find items not in user's group
    local wrongGroup
    wrongGroup=$(/usr/bin/find "$homeDir" ! -group "$group" 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')
    log "Items with incorrect group: $wrongGroup"
    
    if [[ "$wrongOwner" -eq 0 ]] && [[ "$wrongGroup" -eq 0 ]]; then
        log "All permissions are already correct. No changes needed."
        return 0
    fi
    
    # Apply ownership changes recursively
    log "Applying ownership changes..."
    
    # Use chown to fix ownership (recursive)
    if /usr/sbin/chown -R "${user}:${group}" "$homeDir" 2>/dev/null; then
        log "Successfully updated ownership for all items in $homeDir"
    else
        log "WARNING: Some items could not be updated (may be system-protected)"
    fi
    
    # Fix home directory base permissions (750 = owner rwx, group rx, others none)
    /bin/chmod 750 "$homeDir"
    log "Set home directory permissions to 750"
    
    # Verify the fix
    local remainingWrongOwner
    remainingWrongOwner=$(/usr/bin/find "$homeDir" ! -user "$user" 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')
    
    if [[ "$remainingWrongOwner" -gt 0 ]]; then
        log "WARNING: $remainingWrongOwner items still have incorrect ownership (likely system-protected)"
    else
        log "SUCCESS: All items now have correct ownership"
    fi
}

# Display notification to user (optional - requires jamfHelper or osascript)
notify_user() {
    local user="$1"
    local message="$2"
    
    # Use osascript to show notification
    /usr/bin/sudo -u "$user" /usr/bin/osascript -e "display notification \"$message\" with title \"IT Self Service\" sound name \"Glass\""
}

###############################################################################
# Main Script Execution
###############################################################################

log "====== Starting Home Directory Permission Fix ======"

# Get current user
currentUser=$(get_current_user)
log "Current user: $currentUser"

# Validate user
validate_user "$currentUser"

# Get home directory
homeDirectory=$(get_home_directory "$currentUser")

# Get user's primary group
userGroup=$(get_user_group "$currentUser")

# Notify user that process is starting
notify_user "$currentUser" "Fixing home directory permissions. This may take a few minutes..." 2>/dev/null || true

# Fix permissions
fix_permissions "$currentUser" "$homeDirectory" "$userGroup"

# Notify user of completion
notify_user "$currentUser" "Home directory permissions have been fixed successfully." 2>/dev/null || true

log "====== Home Directory Permission Fix Complete ======"

exit 0