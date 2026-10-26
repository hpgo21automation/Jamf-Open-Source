#!/bin/bash
# ==============================================================================
# Anaconda Installer for Jamf Pro
# Downloads the Anaconda installer via Homebrew's cask fetch, then runs it
# directly as root (bypassing the cask install which requires sudo from srv_mac).
# Finally runs conda init zsh for the logged-in user.
# ==============================================================================

HOMEBREW_PREFIX="/opt/homebrew_srv"
BREW_PATH="$HOMEBREW_PREFIX/bin/brew"
SERVICE_USER="srv_mac"
HOMEBREW_CACHE_DIR="$HOMEBREW_PREFIX/cache"
HOMEBREW_LOGS_DIR="$HOMEBREW_PREFIX/logs"
HOMEBREW_TEMP_DIR="$HOMEBREW_PREFIX/tmp"
INSTALL_DIR="/opt/anaconda3"
LOG="/var/log/homebrew_installs.log"

# Tee all output to log file so Jamf captures it in the script result
exec > >(tee -a "$LOG") 2>&1

log() { echo "$(date): $*"; }

log "============================================"
log "Anaconda Install and Setup"
log "============================================"

if [ ! -x "$BREW_PATH" ]; then
    log "ERROR - Homebrew not found at $BREW_PATH. Run the Homebrew installer first."
    exit 1
fi

if ! id "$SERVICE_USER" &>/dev/null; then
    log "ERROR - Service user $SERVICE_USER does not exist"
    exit 1
fi

run_brew() {
    sudo -u "$SERVICE_USER" \
        HOME="$HOMEBREW_PREFIX" \
        HOMEBREW_CACHE="$HOMEBREW_CACHE_DIR" \
        HOMEBREW_LOGS="$HOMEBREW_LOGS_DIR" \
        HOMEBREW_TEMP="$HOMEBREW_TEMP_DIR" \
        HOMEBREW_NO_AUTO_UPDATE=1 \
        HOMEBREW_NO_ENV_HINTS=1 \
        "$BREW_PATH" "$@"
}

# ==============================================================================
# Install Anaconda
# ==============================================================================
if [ -x "$INSTALL_DIR/bin/conda" ]; then
    log "Anaconda already installed at $INSTALL_DIR"
else
    log "Fetching Anaconda installer via Homebrew..."
    run_brew fetch --cask anaconda

    INSTALLER=$(find "$HOMEBREW_CACHE_DIR/Cask" -name "Anaconda3-*.sh" 2>/dev/null | sort -V | tail -1)
    if [ -z "$INSTALLER" ]; then
        log "ERROR - Anaconda installer not found in Homebrew cache after fetch"
        exit 1
    fi

    log "Running installer: $(basename "$INSTALLER")"
    bash "$INSTALLER" -b -p "$INSTALL_DIR"

    if [ $? -ne 0 ]; then
        log "ERROR - Anaconda installer exited with error"
        exit 1
    fi

    # System-wide PATH entry
    echo "$INSTALL_DIR/bin" > /etc/paths.d/anaconda
    chmod 644 /etc/paths.d/anaconda
    log "Added $INSTALL_DIR/bin to /etc/paths.d/anaconda"
fi

CONDA_BIN="$INSTALL_DIR/bin/conda"
if [ ! -x "$CONDA_BIN" ]; then
    log "ERROR - conda binary not found at $CONDA_BIN after install"
    exit 1
fi

log "Anaconda installed: $("$CONDA_BIN" --version 2>&1)"

# ==============================================================================
# Set up conda for the logged-in user
# ==============================================================================
LOGGED_IN_USER=$(stat -f "%Su" /dev/console)

if [ -z "$LOGGED_IN_USER" ] || [ "$LOGGED_IN_USER" = "root" ]; then
    log "No user logged in — skipping conda init. Run 'conda init zsh' manually."
    exit 0
fi

USER_HOME=$(dscl . -read /Users/"$LOGGED_IN_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
if [ -z "$USER_HOME" ]; then
    log "ERROR - Could not determine home directory for $LOGGED_IN_USER"
    exit 1
fi

log "Initialising conda for user: $LOGGED_IN_USER"
sudo -u "$LOGGED_IN_USER" HOME="$USER_HOME" "$CONDA_BIN" init zsh

if [ $? -eq 0 ]; then
    log "Conda setup complete for $LOGGED_IN_USER"
else
    log "ERROR - conda init failed for $LOGGED_IN_USER"
    exit 1
fi

log "============================================"
