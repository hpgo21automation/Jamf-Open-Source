#!/bin/bash
# Extension Attribute: User Homebrew Installations
# Reports any Homebrew installations found in user directories
# Excludes service accounts (srv_*)

found_installations=()

is_service_account() {
    local user="$1"
    [[ "$user" == srv_* || "$user" == "Shared" ]]
}

for user_home in /Users/*/; do
    username=$(basename "$user_home")
    is_service_account "$username" && continue
    
    # Check common Homebrew directory locations
    for brew_dir in "${user_home}homebrew" "${user_home}.homebrew" "${user_home}opt/homebrew"; do
        if [[ -d "$brew_dir" ]]; then
            found_installations+=("$username:$brew_dir")
        fi
    done
    
    # Check for brew binary directly
    if [[ -f "${user_home}homebrew/bin/brew" ]]; then
        [[ ! " ${found_installations[*]} " =~ $username: ]] && found_installations+=("$username:${user_home}homebrew/bin/brew")
    fi
done

if [[ ${#found_installations[@]} -eq 0 ]]; then
    echo "<result>None</result>"
else
    echo "<result>${found_installations[*]}</result>"
fi