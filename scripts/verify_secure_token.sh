#!/bin/bash
###############################################################################
# Secure Token Verification Script
# Reports Secure Token status for all local user accounts
###############################################################################

# Service accounts that don't need Secure Token
SERVICE_ACCOUNTS="srv_mac"

localUsers=$(/usr/bin/dscl . list /Users UniqueID | /usr/bin/awk '$2 >= 500 {print $1}')

echo "=== Secure Token Status Report ==="
echo "Hostname: $(hostname)"
echo "Date: $(date)"
echo "=================================="

tokenFound=false
missingToken=""

for user in $localUsers; do
    tokenStatus=$(/usr/sbin/sysadminctl -secureTokenStatus "$user" 2>&1)
    
    if echo "$tokenStatus" | grep -q "ENABLED"; then
        echo "✅ $user: Secure Token ENABLED"
        tokenFound=true
    else
        # Check if this is a service account
        if echo "$SERVICE_ACCOUNTS" | grep -qw "$user"; then
            echo "⚠️  $user: Secure Token DISABLED (service account - OK)"
        else
            echo "❌ $user: Secure Token DISABLED"
            missingToken="$missingToken $user"
        fi
    fi
done

echo "=================================="

# Check FileVault status
fvStatus=$(fdesetup status 2>&1)
fvEnabled=false
if echo "$fvStatus" | grep -q "FileVault is On"; then
    fvEnabled=true
fi

if [ "$tokenFound" = true ]; then
    echo "Result: At least one account has Secure Token - FileVault can be enabled"
    exit 0
elif [ "$fvEnabled" = false ]; then
    # FileVault not yet enabled — missing SecureToken is expected pre-enrollment
    echo "Result: No Secure Token found, but FileVault is not enabled yet (pre-enrollment OK)"
    exit 0
else
    # FileVault IS enabled but NO user has SecureToken — this is broken
    echo "Result: CRITICAL - FileVault is ON but NO accounts have Secure Token"
    echo "Missing SecureToken users:$missingToken"
    exit 1
fi