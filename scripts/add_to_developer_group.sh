#!/bin/bash
CURRENT_USER=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')

if [[ -z "$CURRENT_USER" ]] || [[ "$CURRENT_USER" == "root" ]]; then
    echo "ERROR: No valid user logged in"
    exit 1
fi

if dsmemberutil checkmembership -U "$CURRENT_USER" -G _developer 2>/dev/null | grep -q "is a member"; then
    echo "$CURRENT_USER is already in the _developer group"
    exit 0
fi

dscl . append /Groups/_developer GroupMembership "$CURRENT_USER"
echo "Added $CURRENT_USER to _developer group"
exit 0
