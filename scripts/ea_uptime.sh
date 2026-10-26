#!/bin/bash
# Uptime Extension Attribute
# Reports the number of days since the last restart.

result=$(uptime | awk '{print $3}' | tr -d ",")

dayCheck=$(uptime | awk '{print $4}' | tr -d ",")
if [ "$dayCheck" != "days" ]; then
    result="1"
fi

echo "<result>$result</result>"