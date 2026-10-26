#!/bin/bash
# Install or Update Podman CLI
# FIX: macOS BSD grep does not support \| alternation in BRE mode.
# The original script used ARCH_PATTERN="aarch64\\|arm64\\|universal" with plain
# `grep -i "$ARCH_PATTERN"`, which treated \| as a literal pipe character on macOS,
# never matching any asset URL. This caused PKG_URL to be empty and the script to
# exit 1 with "ERROR: Could not find Podman pkg installer". Fixed by switching to
# `grep -iE` with standard ERE `|` alternation.
#
# HARDENING (2026-06-16): policy 34 is "Once every week", so a single transient
# failure leaves the policy in Failed state for the whole week. Three holes
# turned transient blips into a weekly-persistent failure:
#   1. `curl -sL -o` did not check exit status or verify the downloaded file
#      was a real pkg (could be empty/HTML on rate-limit redirect).
#   2. `installer -pkg` exit code was unchecked; a failed install would still
#      hit the verify step which only checks `command -v podman` exists — so
#      a partial upgrade would falsely report success.
#   3. No retry around GitHub API fetch or download — a single network blip
#      during the weekly run jams the policy.
# Fix: 3-attempt retry around download+install, file size sanity check,
# installer exit code propagation, and explicit post-install version match
# check (installed == LATEST_VERSION).

LOGFILE="/var/log/podman_install.log"
export PATH="/opt/podman/bin:$PATH"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

# Get current version if installed
CURRENT_VERSION=""
if command -v podman &>/dev/null; then
    CURRENT_VERSION=$(podman --version 2>/dev/null | awk '{print $3}')
    log_message "Current Podman version: $CURRENT_VERSION"
else
    log_message "Podman not installed"
fi

# Get latest release info — retry on transient GitHub API failure
LATEST_INFO=""
for attempt in 1 2 3; do
    LATEST_INFO=$(curl -sL --max-time 30 "https://api.github.com/repos/containers/podman/releases/latest")
    LATEST_VERSION=$(echo "$LATEST_INFO" | grep '"tag_name"' | cut -d '"' -f 4 | sed 's/v//')
    if [[ -n "$LATEST_VERSION" ]]; then
        break
    fi
    if echo "$LATEST_INFO" | grep -q "rate limit"; then
        log_message "WARNING: GitHub API rate limit hit -- skipping update this cycle"
        exit 0
    fi
    log_message "Attempt $attempt: could not determine latest version, retrying in 10s..."
    sleep 10
done

if [[ -z "$LATEST_VERSION" ]]; then
    log_message "ERROR: Could not determine latest version after 3 attempts (last API response: ${LATEST_INFO:0:200})"
    exit 1 # jamf-ci: exit1-intentional
fi

log_message "Latest available version: $LATEST_VERSION"

# Compare versions if already installed
if [[ -n "$CURRENT_VERSION" && "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
    log_message "Podman is already at the latest version"
    exit 0
fi

# Determine action
if [[ -z "$CURRENT_VERSION" ]]; then
    log_message "Installing Podman $LATEST_VERSION..."
else
    log_message "Updating Podman from $CURRENT_VERSION to $LATEST_VERSION..."
fi

# Detect architecture for the right pkg
ARCH=$(uname -m)

# FIX: Use grep -iE with ERE | alternation instead of BRE \| which macOS grep
# does not support. Original: grep -i "aarch64\\|arm64\\|universal"
if [[ "$ARCH" == "arm64" ]]; then
    PKG_URL=$(echo "$LATEST_INFO" | grep "browser_download_url" | grep -iE "\.pkg" | grep -iE "aarch64|arm64|universal" | head -n 1 | cut -d '"' -f 4)
else
    PKG_URL=$(echo "$LATEST_INFO" | grep "browser_download_url" | grep -iE "\.pkg" | grep -iE "amd64|x86_64|universal" | head -n 1 | cut -d '"' -f 4)
fi

if [[ -z "$PKG_URL" ]]; then
    # Fall back to any .pkg in the release
    PKG_URL=$(echo "$LATEST_INFO" | grep "browser_download_url" | grep -iE "\.pkg" | head -n 1 | cut -d '"' -f 4)
fi

if [[ -z "$PKG_URL" ]]; then
    log_message "ERROR: Could not find Podman pkg installer for $ARCH"
    exit 1 # jamf-ci: exit1-intentional
fi

log_message "Downloading from: $PKG_URL"

cd /tmp || exit 1 # jamf-ci: exit1-intentional

# 3-attempt download + install retry. A single transient network blip or
# installer hiccup used to jam this weekly policy for the entire week; now
# it self-heals within the same run.
INSTALL_OK=0
for attempt in 1 2 3; do
    rm -f /tmp/podman.pkg

    if ! curl -fsSL --max-time 120 -o /tmp/podman.pkg "$PKG_URL"; then
        log_message "Attempt $attempt: download failed (curl exit $?), retrying in 15s..."
        sleep 15
        continue
    fi

    # Verify a real pkg landed on disk (>1MB heuristic — Podman pkgs are tens of MB)
    PKG_SIZE=$(stat -f%z /tmp/podman.pkg 2>/dev/null || echo 0)
    if [[ "$PKG_SIZE" -lt 1000000 ]]; then
        log_message "Attempt $attempt: downloaded pkg too small ($PKG_SIZE bytes), likely a redirect/error page, retrying..."
        sleep 15
        continue
    fi

    # Stop podman machine if running (for updates) — best-effort, don't fail on it
    if [[ -n "$CURRENT_VERSION" ]]; then
        podman machine stop 2>/dev/null || true
    fi

    log_message "Attempt $attempt: installing Podman CLI from /tmp/podman.pkg ($PKG_SIZE bytes)..."
    if installer -pkg /tmp/podman.pkg -target / >>"$LOGFILE" 2>&1; then
        INSTALL_OK=1
        break
    fi
    log_message "Attempt $attempt: installer -pkg failed, retrying in 15s..."
    sleep 15
done

rm -f /tmp/podman.pkg

if [[ $INSTALL_OK -ne 1 ]]; then
    log_message "ERROR: Podman install failed after 3 attempts"
    exit 1 # jamf-ci: exit1-intentional
fi

# Verify installation actually produced the target version, not just any
# `podman` binary on PATH (a partial install could leave the old one in place).
if command -v podman &>/dev/null; then
    NEW_VERSION=$(podman --version 2>/dev/null | awk '{print $3}')
    if [[ "$NEW_VERSION" == "$LATEST_VERSION" ]]; then
        log_message "Podman CLI installed successfully: $NEW_VERSION"
        exit 0
    fi
    log_message "ERROR: post-install version mismatch (have $NEW_VERSION, expected $LATEST_VERSION) — installer reported success but did not replace the binary"
    exit 1 # jamf-ci: exit1-intentional
fi
log_message "ERROR: Podman CLI installation failed — podman not found on PATH after installer succeeded"
exit 1 # jamf-ci: exit1-intentional
