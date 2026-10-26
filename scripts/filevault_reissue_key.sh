#!/bin/bash

###############################################################################
# FileVault Recovery Key Reissue Script
# 
# Reissues the personal recovery key and escrows to Jamf Pro
# Run via policy with "Once per computer" or custom trigger
###############################################################################

LOG_FILE="/var/log/example_filevault_rekey.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log "=========================================="
log "FileVault Recovery Key Reissue"
log "=========================================="

# Check FileVault status
fvStatus=$(/usr/bin/fdesetup status)
if [[ "$fvStatus" != *"FileVault is On"* ]]; then
    log "ERROR: FileVault is not enabled"
    exit 1
fi
log "OK: FileVault is enabled"

# Check for logged in user
currentUser=$(stat -f %Su /dev/console)
if [[ "$currentUser" == "root" || "$currentUser" == "loginwindow" || -z "$currentUser" ]]; then
    log "ERROR: No user logged in"
    exit 1
fi
log "OK: User logged in: $currentUser"

# Check if user has SecureToken (required for key change)
if ! /usr/sbin/sysadminctl -secureTokenStatus "$currentUser" 2>&1 | grep -q "ENABLED"; then
    log "ERROR: User $currentUser does not have SecureToken"
    exit 1
fi
log "OK: User has SecureToken"

# Reissue recovery key
log "Reissuing FileVault recovery key..."
if /usr/bin/fdesetup changerecovery -personal 2>&1 | tee -a "$LOG_FILE"; then
    log "=========================================="
    log "SUCCESS: Recovery key reissued"
    log "=========================================="
    exit 0
else
    log "ERROR: Failed to reissue recovery key"
    exit 1
fi