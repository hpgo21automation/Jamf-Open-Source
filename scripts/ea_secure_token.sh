#!/bin/bash
# Extension Attribute: Secure Token Status
# Returns: Username(s) with Secure Token, or "None" if none

tokenUsers=""
localUsers=$(/usr/bin/dscl . list /Users UniqueID | /usr/bin/awk '$2 >= 500 {print $1}')

for user in $localUsers; do
    # Skip service accounts
    [[ "$user" == *srv_* ]] && continue
    
    if /usr/sbin/sysadminctl -secureTokenStatus "$user" 2>&1 | grep -q "ENABLED"; then
        if [[ -z "$tokenUsers" ]]; then
            tokenUsers="$user"
        else
            tokenUsers="$tokenUsers, $user"
        fi
    fi
done

if [[ -z "$tokenUsers" ]]; then
    echo "<result>None</result>"
else
    echo "<result>$tokenUsers</result>"
fi