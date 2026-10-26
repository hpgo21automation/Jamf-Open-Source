#!/bin/bash
# ==============================================================================
# Deploy Homebrew for srv_mac
# Installs Homebrew to /opt/homebrew_srv owned by srv_mac, then configures
# system-wide and per-user PATH. Idempotent — safe to re-run.
# ==============================================================================

SERVICE_USER="srv_mac"
HOMEBREW_PREFIX="/opt/homebrew_srv"
BREW_PATH="$HOMEBREW_PREFIX/bin/brew"
HOMEBREW_CACHE_DIR="$HOMEBREW_PREFIX/cache"
HOMEBREW_LOGS_DIR="$HOMEBREW_PREFIX/logs"
HOMEBREW_TEMP_DIR="$HOMEBREW_PREFIX/tmp"
LOG="/var/log/homebrew_installs.log"
NEWSYSLOG_CONF="/etc/newsyslog.d/homebrew_installs.conf"

# Rotate log now if >10MB (newsyslog handles it going forward)
if [[ -f "$LOG" ]] && [[ $(stat -f%z "$LOG" 2>/dev/null || echo 0) -gt $((10 * 1024 * 1024)) ]]; then
    mv "$LOG" "${LOG}.0" && gzip "${LOG}.0" &
fi

exec > >(tee -a "$LOG") 2>&1

log()  { echo "$(date): $*"; }
info() { echo "$(date): [INFO]  $*"; }
warn() { echo "$(date): [WARN]  $*"; }
err()  { echo "$(date): [ERROR] $*"; }

# Retry helper: runs the given pipeline up to 3 times.
# Uses `set -o pipefail` for the duration so a curl failure piped into tar is
# not masked by tar's success on empty input. Returns the last failing exit.
download_with_retry() {
    local attempt
    local rc=0
    for attempt in 1 2 3; do
        ( set -o pipefail
          curl -fsSL --retry 3 --retry-delay 5 \
            https://github.com/Homebrew/brew/tarball/master \
            | tar xz --strip-components=1 -C "$HOMEBREW_PREFIX" )
        rc=$?
        if [[ $rc -eq 0 ]]; then
            return 0
        fi
        warn "Homebrew tarball download/extract failed on attempt $attempt (exit $rc); retrying in 10s..."
        sleep 10
    done
    return $rc
}

log "============================================"
log "Deploy Homebrew (srv_mac)"
log "Host: $(hostname)"
log "macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
log "Arch: $(uname -m)"
log "============================================"

# Check srv_mac exists
if ! id "$SERVICE_USER" &>/dev/null; then
    err "Service user $SERVICE_USER does not exist — run enrollment first"
    exit 1
fi
info "Service user $SERVICE_USER exists (uid=$(id -u "$SERVICE_USER"))"

# Create required directories
for DIR in "$HOMEBREW_CACHE_DIR" "$HOMEBREW_LOGS_DIR" "$HOMEBREW_TEMP_DIR"; do
    if [[ ! -d "$DIR" ]]; then
        mkdir -p "$DIR"
        chown "$SERVICE_USER:staff" "$DIR"
        chmod 750 "$DIR"
        info "Created directory: $DIR"
    else
        info "Directory already exists: $DIR"
    fi
done

# ==============================================================================
# Install Homebrew if not present
# ==============================================================================
if [[ -x "$BREW_PATH" ]]; then
    BREW_VERSION=$(sudo -u "$SERVICE_USER" \
        HOME="$HOMEBREW_PREFIX" \
        HOMEBREW_NO_AUTO_UPDATE=1 \
        "$BREW_PATH" --version 2>&1 | head -1)
    info "Homebrew already installed: $BREW_VERSION"
else
    info "Homebrew not found at $BREW_PATH — installing..."

    mkdir -p "$HOMEBREW_PREFIX"
    chown "$SERVICE_USER:staff" "$HOMEBREW_PREFIX"
    chmod 750 "$HOMEBREW_PREFIX"
    info "Created $HOMEBREW_PREFIX"

    info "Downloading Homebrew tarball from GitHub (with retry)..."
    if download_with_retry; then
        info "Tarball extracted successfully"
    else
        err "Failed to download or extract Homebrew tarball after 3 attempts"
        exit 1 # jamf-ci: exit1-intentional
    fi

    info "Setting ownership: $SERVICE_USER:staff on $HOMEBREW_PREFIX"
    chown -R "$SERVICE_USER:staff" "$HOMEBREW_PREFIX"
    chmod -R 750 "$HOMEBREW_PREFIX"

    info "Verifying Homebrew installation..."
    BREW_VERSION=$(sudo -u "$SERVICE_USER" \
        HOME="$HOMEBREW_PREFIX" \
        HOMEBREW_CACHE="$HOMEBREW_CACHE_DIR" \
        HOMEBREW_LOGS="$HOMEBREW_LOGS_DIR" \
        HOMEBREW_TEMP="$HOMEBREW_TEMP_DIR" \
        HOMEBREW_NO_AUTO_UPDATE=1 \
        "$BREW_PATH" --version 2>&1 | head -1)

    if [[ -n "$BREW_VERSION" ]]; then
        info "Homebrew installed successfully: $BREW_VERSION"
    else
        err "Homebrew installation failed — brew --version returned nothing"
        exit 1 # jamf-ci: exit1-intentional
    fi
fi

# ==============================================================================
# Configure PATH (idempotent)
# ==============================================================================
info "--- Configuring system PATH ---"

# /etc/paths.d — picked up by path_helper for all login shells
PATHS_FILE="/etc/paths.d/homebrew_srv"
if [[ ! -f "$PATHS_FILE" ]]; then
    printf "%s\n%s\n" "$HOMEBREW_PREFIX/bin" "$HOMEBREW_PREFIX/sbin" > "$PATHS_FILE"
    chmod 644 "$PATHS_FILE"
    info "Created $PATHS_FILE"
else
    info "$PATHS_FILE already exists — skipping"
fi

# /etc/zprofile — zsh login shells
ZPROFILE="/etc/zprofile"
if ! grep -q "homebrew_srv" "$ZPROFILE" 2>/dev/null; then
    cat >> "$ZPROFILE" << 'ZSHEOF'

# Example Homebrew PATH
export PATH="/opt/homebrew_srv/bin:/opt/homebrew_srv/sbin:$PATH"
ZSHEOF
    info "Added Homebrew PATH to $ZPROFILE"
else
    info "$ZPROFILE already configured — skipping"
fi

# /etc/profile.d — bash login shells
PROFILE_D="/etc/profile.d/homebrew_srv.sh"
if [[ ! -f "$PROFILE_D" ]]; then
    mkdir -p /etc/profile.d
    cat > "$PROFILE_D" << 'SHELLEOF'
# Example Homebrew PATH
export PATH="/opt/homebrew_srv/bin:/opt/homebrew_srv/sbin:$PATH"
SHELLEOF
    chmod 644 "$PROFILE_D"
    info "Created $PROFILE_D"
else
    info "$PROFILE_D already exists — skipping"
fi

# Per-user shell configs
info "--- Configuring per-user shell configs ---"
PATH_SNIPPET='
# Example Homebrew PATH
export PATH="/opt/homebrew_srv/bin:/opt/homebrew_srv/sbin:$PATH"'

USERS_UPDATED=0
USERS_SKIPPED=0

for USER_HOME in /Users/*; do
    [[ -d "$USER_HOME" ]] && [[ "$USER_HOME" != "/Users/Shared" ]] || continue
    USERNAME=$(basename "$USER_HOME")
    id "$USERNAME" &>/dev/null || continue

    ZSHRC="$USER_HOME/.zshrc"
    if [[ ! -f "$ZSHRC" ]]; then
        echo "$PATH_SNIPPET" > "$ZSHRC"
        chown "$USERNAME:staff" "$ZSHRC"
        chmod 644 "$ZSHRC"
        info "[$USERNAME] Created .zshrc with Homebrew PATH"
        (( USERS_UPDATED++ ))
    elif ! grep -q "homebrew_srv" "$ZSHRC" 2>/dev/null; then
        echo "$PATH_SNIPPET" >> "$ZSHRC"
        info "[$USERNAME] Added Homebrew PATH to existing .zshrc"
        (( USERS_UPDATED++ ))
    else
        info "[$USERNAME] .zshrc already configured — skipping"
        (( USERS_SKIPPED++ ))
    fi

    BASH_PROFILE="$USER_HOME/.bash_profile"
    if [[ -f "$BASH_PROFILE" ]] && ! grep -q "homebrew_srv" "$BASH_PROFILE" 2>/dev/null; then
        echo "$PATH_SNIPPET" >> "$BASH_PROFILE"
        info "[$USERNAME] Added Homebrew PATH to .bash_profile"
    fi
done

info "Per-user config complete: $USERS_UPDATED updated, $USERS_SKIPPED already configured"

# ==============================================================================
# Configure log rotation via newsyslog (macOS native)
# Rotates at 10MB, keeps 5 compressed archives
# ==============================================================================
if [[ ! -f "$NEWSYSLOG_CONF" ]]; then
    cat > "$NEWSYSLOG_CONF" << 'NEWSYSLOGEOF'
# logfilename                        [owner:group]  mode  count  size   when  flags
/var/log/homebrew_installs.log       root:wheel     644   5      10240  *     J
NEWSYSLOGEOF
    chmod 644 "$NEWSYSLOG_CONF"
    info "Created newsyslog config: $NEWSYSLOG_CONF (rotate at 10MB, keep 5)"
else
    info "newsyslog config already exists — skipping"
fi

log "============================================"
log "Deploy Homebrew complete"
log "============================================"

exit 0
