#!/bin/bash
version=$(defaults read /Library/Preferences/com.example.splunk InputsScriptVersion 2>/dev/null || echo "none")
echo "<result>$version</result>"