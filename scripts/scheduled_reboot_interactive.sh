#!/bin/bash

###############################################################################
# Interactive Scheduled Reboot - 8 hours after enrollment
# Prompts user with countdown and snooze options
# Skips if machine was rebooted recently
###############################################################################

REQUIRED_UPTIME=28800  # 8 hours in seconds
SNOOZE_TIME=3600       # 1 hour snooze
MAX_SNOOZES=3          # Maximum snooze attempts

currentUser=$(/usr/bin/stat -f "%Su" /dev/console)

# Get uptime in seconds
uptimeSeconds=$(sysctl -n kern.boottime | awk '{print $4}' | sed 's/,//')
currentTime=$(date +%s)
bootTime=$uptimeSeconds
uptime=$((currentTime - bootTime))

echo "Current uptime: $uptime seconds"

# If uptime is less than 8 hours, machine was rebooted recently - skip
if [ $uptime -lt $REQUIRED_UPTIME ]; then
    echo "Machine was rebooted within the last 8 hours. Uptime: $((uptime / 3600)) hours. Skipping reboot prompt."
    exit 0
fi

echo "Machine has been up for $((uptime / 3600)) hours. Prompting for reboot."

if [ "$currentUser" = "root" ] || [ -z "$currentUser" ]; then
    echo "No user logged in, scheduling silent reboot"
    /sbin/shutdown -r +10
    exit 0
fi

currentUserUID=$(/usr/bin/id -u "$currentUser")

snoozeCount=0

while true; do
    # Re-check uptime in case user rebooted during snooze
    uptimeSeconds=$(sysctl -n kern.boottime | awk '{print $4}' | sed 's/,//')
    currentTime=$(date +%s)
    bootTime=$uptimeSeconds
    uptime=$((currentTime - bootTime))
    
    if [ $uptime -lt $REQUIRED_UPTIME ]; then
        echo "Machine was rebooted during snooze period. Exiting."
        exit 0
    fi

    # Prompt user
    userChoice=$(/bin/launchctl asuser "$currentUserUID" /usr/bin/osascript <<EOF
set theChoice to button returned of (display dialog "Example IT requires a restart to complete setup.

Please save your work and click 'Restart Now'.

You can postpone up to $((MAX_SNOOZES - snoozeCount)) more time(s)." ¬
buttons {"Postpone 1 Hour", "Restart Now"} ¬
default button "Restart Now" ¬
with title "Restart Required" ¬
with icon caution ¬
giving up after 300)

if theChoice is "" then
    return "timeout"
else
    return theChoice
end if
EOF
)

    if [ "$userChoice" = "Restart Now" ] || [ "$userChoice" = "timeout" ]; then
        # Notify and reboot
        /bin/launchctl asuser "$currentUserUID" /usr/bin/osascript -e 'display notification "Restarting in 60 seconds..." with title "Example IT"'
        sleep 60
        /sbin/shutdown -r now
        exit 0
    elif [ "$userChoice" = "Postpone 1 Hour" ]; then
        snoozeCount=$((snoozeCount + 1))
        
        if [ $snoozeCount -ge $MAX_SNOOZES ]; then
            # Max snoozes reached, force reboot
            /bin/launchctl asuser "$currentUserUID" /usr/bin/osascript -e 'display dialog "Maximum postponements reached. Your Mac will restart in 2 minutes." buttons {"OK"} default button "OK" with title "Restart Required" with icon stop'
            sleep 120
            /sbin/shutdown -r now
            exit 0
        fi
        
        # Snooze for 1 hour
        /bin/launchctl asuser "$currentUserUID" /usr/bin/osascript -e 'display notification "Restart postponed. You will be prompted again in 1 hour." with title "Example IT"'
        sleep $SNOOZE_TIME
    fi
done