#!/bin/bash
# ==============================================================================
# Install Xcode Command Line Tools
# ==============================================================================
# Handles edge cases where CLT appears installed but xcode-select doesn't see it
# ==============================================================================

set -euo pipefail

LOG_PREFIX="[Xcode CLT]"

echo "$LOG_PREFIX Starting Xcode Command Line Tools installation check..."

# ==============================================================================
# Check 1: xcode-select path exists
# ==============================================================================
if xcode-select -p &>/dev/null; then
    CLT_PATH=$(xcode-select -p)
    echo "$LOG_PREFIX Already installed at: $CLT_PATH"
    exit 0
fi

# ==============================================================================
# Check 2: Directory exists but xcode-select not configured
# ==============================================================================
if [[ -d "/Library/Developer/CommandLineTools" ]]; then
    echo "$LOG_PREFIX Directory exists, configuring xcode-select..."
    xcode-select --switch /Library/Developer/CommandLineTools
    
    if xcode-select -p &>/dev/null; then
        echo "$LOG_PREFIX Configured successfully at: $(xcode-select -p)"
        exit 0
    fi
fi

# ==============================================================================
# Check 3: Full Xcode is installed (CLT included)
# ==============================================================================
if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    echo "$LOG_PREFIX Full Xcode detected, configuring xcode-select..."
    xcode-select --switch /Applications/Xcode.app/Contents/Developer
    
    if xcode-select -p &>/dev/null; then
        echo "$LOG_PREFIX Configured to use Xcode.app at: $(xcode-select -p)"
        exit 0
    fi
fi

# ==============================================================================
# Install: Need to download CLT
# ==============================================================================
echo "$LOG_PREFIX Command Line Tools not found, initiating install..."

# Create placeholder file to trigger softwareupdate to list CLT
PLACEHOLDER="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
touch "$PLACEHOLDER"

# Give software update a moment to recognize the placeholder
sleep 3

# Get the full softwareupdate output for debugging
echo "$LOG_PREFIX Checking available updates..."
SWUPDATE_OUTPUT=$(softwareupdate -l 2>&1) || true
echo "$LOG_PREFIX Software Update output:"
echo "$SWUPDATE_OUTPUT"

# Try multiple patterns to find the CLT package name
CLT_PACKAGE=""

# Pattern 1: Look for "Label: Command Line Tools..."
if [[ -z "$CLT_PACKAGE" ]]; then
    CLT_PACKAGE=$(echo "$SWUPDATE_OUTPUT" | grep -E "Label:.*Command Line" | sed 's/^.*Label: //' | head -n 1 | xargs)
fi

# Pattern 2: Look for "* Command Line Tools..." (asterisk format)
if [[ -z "$CLT_PACKAGE" ]]; then
    CLT_PACKAGE=$(echo "$SWUPDATE_OUTPUT" | grep -E "^\s*\*.*Command Line" | sed 's/^[[:space:]]*\*[[:space:]]*//' | head -n 1 | xargs)
fi

# Pattern 3: Extract "Command Line Tools for Xcode-X.X" pattern
if [[ -z "$CLT_PACKAGE" ]]; then
    CLT_PACKAGE=$(echo "$SWUPDATE_OUTPUT" | grep -oE "Command Line Tools for Xcode-[0-9.]+" | head -n 1)
fi

# Pattern 4: Extract "Command Line Tools-X.X" pattern (older format)
if [[ -z "$CLT_PACKAGE" ]]; then
    CLT_PACKAGE=$(echo "$SWUPDATE_OUTPUT" | grep -oE "Command Line Tools-[0-9.]+" | head -n 1)
fi

# NOTE: placeholder is kept alive until after the install attempt below.
# Removing it before softwareupdate -i causes "No such update" because
# the placeholder is what makes CLT appear in the softwareupdate catalog.

# ==============================================================================
# Handle: No CLT package found in updates
# ==============================================================================
if [[ -z "$CLT_PACKAGE" ]]; then
    echo "$LOG_PREFIX No Command Line Tools package found in software update"
    
    # Final check - maybe it installed during our check
    if [[ -d "/Library/Developer/CommandLineTools/usr/bin/git" ]]; then
        echo "$LOG_PREFIX CLT appears to be installed (git binary exists)"
        xcode-select --switch /Library/Developer/CommandLineTools 2>/dev/null || true
        exit 0
    fi
    
    # On newer macOS, try xcode-select --install trigger
    echo "$LOG_PREFIX Attempting xcode-select --install method..."
    
    # This normally triggers a GUI prompt, but in some contexts it works headlessly
    xcode-select --install 2>/dev/null &
    INSTALL_PID=$!
    
    # Wait up to 60 seconds for installation to start/complete
    for _ in {1..12}; do
        sleep 5
        if [[ -d "/Library/Developer/CommandLineTools/usr/bin/git" ]]; then
            echo "$LOG_PREFIX Installation detected after xcode-select --install"
            xcode-select --switch /Library/Developer/CommandLineTools 2>/dev/null || true
            kill $INSTALL_PID 2>/dev/null || true
            exit 0
        fi
    done
    
    echo "$LOG_PREFIX ERROR: Could not install Command Line Tools automatically"
    echo "$LOG_PREFIX This Mac may require manual installation via System Settings > Software Update"
    exit 1
fi

# ==============================================================================
# Install: Found package, attempt installation
# ==============================================================================
echo "$LOG_PREFIX Found package: $CLT_PACKAGE"
echo "$LOG_PREFIX Installing..."

# Attempt the install — keep placeholder alive so CLT stays in the catalog
INSTALL_RESULT=0
softwareupdate -i "$CLT_PACKAGE" --agree-to-license --verbose 2>&1 || INSTALL_RESULT=$?

# macOS 26+ label is "Product OS_VER-PKG_VER" but installer may need "Product-PKG_VER"
if [[ $INSTALL_RESULT -ne 0 ]]; then
    BASE_NAME=$(echo "$CLT_PACKAGE" | sed 's/[[:space:]][0-9][0-9.]*-[0-9].*//')
    PKG_VERSION=$(echo "$CLT_PACKAGE" | grep -oE '[0-9][0-9.]*$')
    ALT_PACKAGE="${BASE_NAME}-${PKG_VERSION}"
    if [[ -n "$PKG_VERSION" ]] && [[ "$ALT_PACKAGE" != "$CLT_PACKAGE" ]]; then
        echo "$LOG_PREFIX Retrying with alternate identifier: $ALT_PACKAGE"
        INSTALL_RESULT=0
        softwareupdate -i "$ALT_PACKAGE" --agree-to-license --verbose 2>&1 || INSTALL_RESULT=$?
    fi
fi

# Placeholder no longer needed — remove after all install attempts
rm -f "$PLACEHOLDER"

# Check if "No such update" error occurred
if [[ $INSTALL_RESULT -ne 0 ]]; then
    echo "$LOG_PREFIX softwareupdate returned error code: $INSTALL_RESULT"

    # Even with an error, check if CLT got installed anyway (common with "Error installing updates")
    if [[ -d "/Library/Developer/CommandLineTools/usr/bin/git" ]]; then
        echo "$LOG_PREFIX Despite error, CLT appears installed"
        xcode-select --switch /Library/Developer/CommandLineTools 2>/dev/null || true
        if xcode-select -p &>/dev/null; then
            echo "$LOG_PREFIX Successfully configured at: $(xcode-select -p)"
            exit 0
        fi
    fi

    # softwareupdate sometimes downloads but fails to run the installer pkg.
    # Find the downloaded pkg in /Library/Updates and install directly.
    echo "$LOG_PREFIX Searching for downloaded CLT package in /Library/Updates..."
    CACHED_PKG=$(find /Library/Updates -name "*.pkg" 2>/dev/null | grep -i "CommandLine" | head -1)
    if [[ -n "$CACHED_PKG" ]]; then
        echo "$LOG_PREFIX Found cached pkg: $CACHED_PKG — installing directly..."
        installer -pkg "$CACHED_PKG" -target / 2>&1 || true
        if xcode-select -p &>/dev/null; then
            echo "$LOG_PREFIX Installed via direct pkg at: $(xcode-select -p)"
            exit 0
        fi
        if [[ -d "/Library/Developer/CommandLineTools" ]]; then
            xcode-select --switch /Library/Developer/CommandLineTools 2>/dev/null || true
            if xcode-select -p &>/dev/null; then
                echo "$LOG_PREFIX Configured after direct pkg install: $(xcode-select -p)"
                exit 0
            fi
        fi
    fi

    # Check if it was already installed (the "No such update" case)
    if [[ -d "/Library/Developer/CommandLineTools" ]]; then
        echo "$LOG_PREFIX CLT directory exists, attempting to configure..."
        xcode-select --switch /Library/Developer/CommandLineTools 2>/dev/null || true
        if xcode-select -p &>/dev/null; then
            echo "$LOG_PREFIX Successfully configured at: $(xcode-select -p)"
            exit 0
        fi
    fi
fi

# ==============================================================================
# Verify: Final installation check
# ==============================================================================
sleep 2

if xcode-select -p &>/dev/null; then
    echo "$LOG_PREFIX Installation successful at: $(xcode-select -p)"
    exit 0
fi

# One more attempt to switch if directory exists
if [[ -d "/Library/Developer/CommandLineTools" ]]; then
    xcode-select --switch /Library/Developer/CommandLineTools 2>/dev/null || true
    
    if xcode-select -p &>/dev/null; then
        echo "$LOG_PREFIX Installation successful at: $(xcode-select -p)"
        exit 0
    fi
fi

# Check for the actual tools
if [[ -x "/Library/Developer/CommandLineTools/usr/bin/git" ]]; then
    echo "$LOG_PREFIX CLT binaries exist but xcode-select not configured"
    echo "$LOG_PREFIX Forcing xcode-select path..."
    xcode-select -s /Library/Developer/CommandLineTools
    exit 0
fi

echo "$LOG_PREFIX ERROR: Installation could not be verified"
echo "$LOG_PREFIX Manual intervention may be required"
exit 1 # jamf-ci: exit1-intentional — policy is Ongoing; failure triggers re-run