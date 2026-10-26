#!/bin/bash
if [[ $(uname -m) == "arm64" ]]; then
    # Check for the Rosetta binary itself
    if [[ ! -f "/Library/Apple/usr/share/rosetta/rosetta" ]]; then
        echo "Installing Rosetta..."
        if /usr/sbin/softwareupdate --install-rosetta --agree-to-license; then
            echo "Rosetta installed successfully."
        else
            echo "Error: Rosetta installation failed." >&2
            exit 1
        fi
    else
        echo "Rosetta is already installed."
    fi
else
    echo "Not Apple Silicon - skipping."
fi
exit 0