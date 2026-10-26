#!/bin/bash
# ==============================================================================
# Homebrew Package Installer for Jamf Pro
# ==============================================================================
# Parameters:
#   $4 = Formula/cask token (required)
#   $5 = Tap (optional, e.g., "ahmetb/kubectx")
#   $6 = Type: "formula" (default) or "cask"
# ==============================================================================

set -uo pipefail

# Variables
SERVICE_USER="srv_mac"
HOMEBREW_PREFIX="/opt/homebrew_srv"
BREW_PATH="$HOMEBREW_PREFIX/bin/brew"
HOMEBREW_CACHE_DIR="$HOMEBREW_PREFIX/cache"
HOMEBREW_LOGS_DIR="$HOMEBREW_PREFIX/logs"
HOMEBREW_TEMP_DIR="$HOMEBREW_PREFIX/tmp"
HOMEBREW_SSL_DIR="$HOMEBREW_PREFIX/etc/ssl/certs"
LOG="/var/log/homebrew_installs.log"

# Rotate log if >10MB (newsyslog handles ongoing rotation after first deploy)
if [[ -f "$LOG" ]] && [[ $(stat -f%z "$LOG" 2>/dev/null || echo 0) -gt $((10 * 1024 * 1024)) ]]; then
    mv "$LOG" "${LOG}.0" && gzip "${LOG}.0" &
fi

# Preserve Jamf's stdout fd, then redirect through tee for log + terminal
exec 3>&1
exec > >(tee -a "$LOG") 2>&1

# On any exit: (1) print the last 80 log lines back to Jamf's stdout so the
# policy result is populated, and (2) record a per-formula last-run status for
# the "Homebrew Install Failures" EA, so the daily compliance check can read
# which package failed and why straight from inventory.
STATUS_DIR="/Library/Application Support/Example/jamf-status"
on_exit() {
    local rc=$?
    echo
    echo "=== homebrew_installs.log (last 80 lines) ==="
    tail -80 "$LOG" >&3 2>/dev/null || true

    local slug="${FORMULA//\//_}"
    [[ -z "$slug" ]] && slug="unknown"
    mkdir -p "$STATUS_DIR" 2>/dev/null || return 0
    local ts
    ts=$(date '+%Y-%m-%dT%H:%M:%S')
    if [[ $rc -eq 0 ]]; then
        printf 'OK|%s|%s|\n' "$ts" "$FORMULA" \
            > "$STATUS_DIR/homebrew-install-$slug.status" 2>/dev/null || true
    else
        local reason
        reason=$(grep -iE 'ERROR' "$LOG" 2>/dev/null | tail -1 | cut -c1-200)
        printf 'FAIL|%s|%s|%s\n' "$ts" "$FORMULA" "${reason:-exit $rc}" \
            > "$STATUS_DIR/homebrew-install-$slug.status" 2>/dev/null || true
    fi
}
trap on_exit EXIT

FORMULA="${4:-}"
TAP="${5:-}"
PKG_TYPE="${6:-formula}"

# Casks are GUI .app/.pkg installs. They go to /Applications (system-wide) so
# every user sees the app, and are managed via `brew install --cask`. When a
# package is a cask we pass --cask to all brew subcommands via $CASK_FLAG.
# A plain string (not an array) so unquoted expansion is empty for formulas —
# avoids the bash 3.2 "unbound variable" on empty-array expansion under set -u.
IS_CASK=0
CASK_FLAG=""
if [[ "$PKG_TYPE" == "cask" ]]; then
    IS_CASK=1
    CASK_FLAG="--cask"
fi

# Common keg-only formulas that have useful binaries
# Format: "formula:relative_bin_path" (relative to $HOMEBREW_PREFIX/opt/)
KEG_ONLY_FORMULAS=(
    "libpq:libpq/bin"
    "curl:curl/bin"
    "openssl@3:openssl@3/bin"
    "openssl@1.1:openssl@1.1/bin"
    "sqlite:sqlite/bin"
    "libxml2:libxml2/bin"
    "libxslt:libxslt/bin"
    "icu4c:icu4c/bin"
    "ncurses:ncurses/bin"
    "ruby:ruby/bin"
    "python@3.11:python@3.11/bin"
    "python@3.12:python@3.12/bin"
    "mysql-client:mysql-client/bin"
    "postgresql@14:postgresql@14/bin"
    "postgresql@15:postgresql@15/bin"
    "postgresql@16:postgresql@16/bin"
)

echo "============================================" >> "$LOG"
echo "$(date): Homebrew Package Installer" >> "$LOG"
echo "Token: $FORMULA" >> "$LOG"
echo "Type: $PKG_TYPE" >> "$LOG"
echo "Tap: ${TAP:-none}" >> "$LOG"
echo "============================================" >> "$LOG"

if [[ -z "$FORMULA" ]]; then
    echo "$(date): ERROR - No formula specified in parameter 4" >> "$LOG"
    exit 1
fi

# Check if srv_mac exists
if ! id "$SERVICE_USER" &>/dev/null; then
    echo "$(date): ERROR - User $SERVICE_USER does not exist" >> "$LOG"
    exit 1
fi

# Create cache, logs, temp, and SSL directories for srv_mac
for DIR in "$HOMEBREW_CACHE_DIR" "$HOMEBREW_LOGS_DIR" "$HOMEBREW_TEMP_DIR" "$HOMEBREW_SSL_DIR"; do
    if [[ ! -d "$DIR" ]]; then
        echo "$(date): Creating $DIR..." >> "$LOG"
        mkdir -p "$DIR"
    fi
done
# mkdir -p creates intermediate dirs (e.g. /opt/homebrew_srv/etc) as root.
# Fix ownership of entire prefix so srv_mac can write everywhere.
chown -R "$SERVICE_USER:staff" "$HOMEBREW_PREFIX"

# Formulae whose bottles bake in HOMEBREW_PREFIX (node, openssl@3, pkgconf,
# python@3.x) cannot be poured at our non-standard prefix, so they are compiled
# from source — which needs a CLT whose major version is at least the macOS major
# version (Library/Homebrew/os/mac/xcode.rb: CLT.minimum_version falls through to
# "<macos_major>.0.0"). A CLT left behind by a macOS upgrade still satisfies
# `xcode-select -p`, so a presence-only check passes here and brew fails much
# later with "Your Command Line Tools are too outdated" mid-build.
clt_installed_version() {
    pkgutil --pkg-info=com.apple.pkg.CLTools_Executables 2>/dev/null |
        awk '/^version:/ { print $2; exit }'
}

clt_needs_install() {
    if ! xcode-select -p &>/dev/null; then
        return 0
    fi

    local installed clt_major macos_major
    installed=$(clt_installed_version)
    clt_major=${installed%%.*}
    macos_major=$(sw_vers -productVersion | cut -d. -f1)

    # Anything unparseable is treated as "needs install" — failing safe here is
    # cheaper than letting brew discover the problem mid-build.
    if [[ ! "$clt_major" =~ ^[0-9]+$ ]] || [[ ! "$macos_major" =~ ^[0-9]+$ ]]; then
        return 0
    fi

    (( clt_major < macos_major ))
}

# Check and install/update Xcode Command Line Tools (required by Homebrew)
if clt_needs_install; then
    echo "$(date): Xcode CLT missing or outdated (installed: $(clt_installed_version || true), macOS: $(sw_vers -productVersion)). Installing..." >> "$LOG"
    echo "Xcode CLT missing or outdated - attempting install..."

    PLACEHOLDER="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
    touch "$PLACEHOLDER"
    sleep 3
    SWUPDATE_OUT=$(softwareupdate -l 2>&1) || true
    # Placeholder stays alive until after install

    CLT_PACKAGE=""
    CLT_PACKAGE=$(echo "$SWUPDATE_OUT" | grep -E "Label:.*Command Line" | sed 's/^.*Label: //' | head -n 1 | xargs) || true
    if [[ -z "$CLT_PACKAGE" ]]; then
        CLT_PACKAGE=$(echo "$SWUPDATE_OUT" | grep -oE "Command Line Tools for Xcode-[0-9.]+" | head -n 1) || true
    fi

    if [[ -n "$CLT_PACKAGE" ]]; then
        echo "Found CLT package: $CLT_PACKAGE"
        echo "$(date): Installing $CLT_PACKAGE..." >> "$LOG"
        INSTALL_RESULT=0
        softwareupdate -i "$CLT_PACKAGE" --agree-to-license --verbose 2>&1 | tee -a "$LOG" || INSTALL_RESULT=$?

        if [[ $INSTALL_RESULT -ne 0 ]]; then
            BASE=$(echo "$CLT_PACKAGE" | sed 's/[[:space:]][0-9][0-9.]*-[0-9].*//')
            VER=$(echo "$CLT_PACKAGE" | grep -oE '[0-9][0-9.]*$')
            ALT="${BASE}-${VER}"
            if [[ -n "$VER" ]] && [[ "$ALT" != "$CLT_PACKAGE" ]]; then
                echo "Retrying CLT install with alternate identifier: $ALT"
                softwareupdate -i "$ALT" --agree-to-license --verbose 2>&1 | tee -a "$LOG" || true
            fi
            # softwareupdate may download but fail to install - try direct pkg
            CACHED_PKG=$(find /Library/Updates -name "*.pkg" 2>/dev/null | grep -i "CommandLine" | head -1)
            if [[ -n "$CACHED_PKG" ]]; then
                echo "Installing CLT via direct pkg: $CACHED_PKG"
                installer -pkg "$CACHED_PKG" -target / 2>&1 | tee -a "$LOG" || true
            fi
        fi
    else
        echo "WARNING: CLT not found in softwareupdate catalog"
    fi

    rm -f "$PLACEHOLDER"

    if [[ -d "/Library/Developer/CommandLineTools" ]]; then
        xcode-select --switch /Library/Developer/CommandLineTools 2>/dev/null || true
    fi

    if clt_needs_install; then
        echo "$(date): ERROR - Xcode CLT installation failed" >> "$LOG"
        echo "ERROR: Xcode CLT missing or too outdated for macOS $(sw_vers -productVersion), and could not be installed."
        echo "Installed CLT version: $(clt_installed_version || true)"
        echo "Run the 'Install xcode CLI tools' policy on this machine first, then retry."
        exit 1
    fi
    echo "$(date): Xcode CLT $(clt_installed_version) ready at $(xcode-select -p)" >> "$LOG"
    echo "Xcode CLT $(clt_installed_version) ready at $(xcode-select -p)"
fi

# ==============================================================================
# Extract and set up CA certificates for Node.js/npm
# Homebrew-built Node.js is missing ISRG Root X1 (Let's Encrypt) from its
# bundled CA store. We extract it from macOS System Keychain.
# ==============================================================================
setup_ca_certificates() {
    echo "$(date): Setting up CA certificates for Node.js..." >> "$LOG"
    
    local ISRG_CERT="$HOMEBREW_SSL_DIR/isrg-root-x1.pem"
    local COMBINED_BUNDLE="$HOMEBREW_SSL_DIR/ca-bundle.pem"
    
    # Extract ISRG Root X1 from macOS System Keychain if not already done
    if [[ ! -f "$ISRG_CERT" ]]; then
        echo "$(date): Extracting ISRG Root X1 certificate from System Keychain..." >> "$LOG"
        if security find-certificate -c "ISRG Root X1" -p \
            /System/Library/Keychains/SystemRootCertificates.keychain > "$ISRG_CERT" 2>/dev/null; then
            chown "$SERVICE_USER:staff" "$ISRG_CERT"
            chmod 644 "$ISRG_CERT"
            echo "$(date): ISRG Root X1 certificate extracted to $ISRG_CERT" >> "$LOG"
        else
            echo "$(date): WARNING - Could not extract ISRG Root X1 certificate" >> "$LOG"
        fi
    fi
    
    # Create combined CA bundle (system certs + ISRG Root X1)
    if [[ ! -f "$COMBINED_BUNDLE" ]] || [[ "$ISRG_CERT" -nt "$COMBINED_BUNDLE" ]]; then
        echo "$(date): Creating combined CA bundle..." >> "$LOG"
        
        # Start with system CA bundle
        if [[ -f "/etc/ssl/cert.pem" ]]; then
            cp /etc/ssl/cert.pem "$COMBINED_BUNDLE"
        elif [[ -f "/private/etc/ssl/cert.pem" ]]; then
            cp /private/etc/ssl/cert.pem "$COMBINED_BUNDLE"
        else
            : > "$COMBINED_BUNDLE"
        fi
        
        # Append ISRG Root X1 if it exists and isn't already in the bundle
        if [[ -f "$ISRG_CERT" ]]; then
            if ! grep -q "ISRG Root X1" "$COMBINED_BUNDLE" 2>/dev/null; then
                echo "" >> "$COMBINED_BUNDLE"
                echo "# ISRG Root X1 (Let's Encrypt)" >> "$COMBINED_BUNDLE"
                cat "$ISRG_CERT" >> "$COMBINED_BUNDLE"
                echo "$(date): Added ISRG Root X1 to combined bundle" >> "$LOG"
            fi
        fi
        
        chown "$SERVICE_USER:staff" "$COMBINED_BUNDLE"
        chmod 644 "$COMBINED_BUNDLE"
        echo "$(date): Combined CA bundle created at $COMBINED_BUNDLE" >> "$LOG"
    fi
}

# ==============================================================================
# Determine CA certificate bundle location
# ==============================================================================
get_ca_bundle() {
    local COMBINED_BUNDLE="$HOMEBREW_SSL_DIR/ca-bundle.pem"
    
    if [[ -f "$COMBINED_BUNDLE" ]]; then
        echo "$COMBINED_BUNDLE"
    elif [[ -f "$HOMEBREW_PREFIX/etc/ca-certificates/cert.pem" ]]; then
        echo "$HOMEBREW_PREFIX/etc/ca-certificates/cert.pem"
    elif [[ -f "$HOMEBREW_PREFIX/etc/openssl@3/cert.pem" ]]; then
        echo "$HOMEBREW_PREFIX/etc/openssl@3/cert.pem"
    elif [[ -f "/etc/ssl/cert.pem" ]]; then
        echo "/etc/ssl/cert.pem"
    else
        echo ""
    fi
}

# ==============================================================================
# Set up XML catalogs for docbook (required for packages that build docs)
# ==============================================================================
setup_xml_catalogs() {
    echo "$(date): Setting up XML catalogs..." >> "$LOG"
    
    # Create /etc/xml directory if needed
    if [[ ! -d "/etc/xml" ]]; then
        mkdir -p /etc/xml
    fi
    chmod 775 /etc/xml 2>/dev/null || true
    chgrp staff /etc/xml 2>/dev/null || true
    
    # Create Homebrew's etc/xml directory for catalogs
    if [[ ! -d "$HOMEBREW_PREFIX/etc/xml" ]]; then
        mkdir -p "$HOMEBREW_PREFIX/etc/xml"
        chown "$SERVICE_USER:staff" "$HOMEBREW_PREFIX/etc/xml"
        chmod 755 "$HOMEBREW_PREFIX/etc/xml"
    fi
    
    # Initialize the catalog file if it doesn't exist
    local CATALOG_FILE="$HOMEBREW_PREFIX/etc/xml/catalog"
    if [[ ! -f "$CATALOG_FILE" ]]; then
        echo "$(date): Creating initial XML catalog at $CATALOG_FILE..." >> "$LOG"
        cat > "$CATALOG_FILE" << 'CATALOGEOF'
<?xml version="1.0"?>
<!DOCTYPE catalog PUBLIC "-//OASIS//DTD XML Catalogs V1.1//EN" "http://www.oasis-open.org/committees/entity/release/1.1/catalog.dtd">
<catalog xmlns="urn:oasis:names:tc:entity:xmlns:xml:catalog">
</catalog>
CATALOGEOF
        chown "$SERVICE_USER:staff" "$CATALOG_FILE"
        chmod 644 "$CATALOG_FILE"
    fi
    
    # Run docbook postinstall if installed (registers its catalogs)
    if run_brew list docbook &>/dev/null 2>&1; then
        echo "$(date): Running docbook postinstall..." >> "$LOG"
        run_brew postinstall docbook >> "$LOG" 2>&1 || true
    fi
    
    if run_brew list docbook-xsl &>/dev/null 2>&1; then
        echo "$(date): Running docbook-xsl postinstall..." >> "$LOG"
        run_brew postinstall docbook-xsl >> "$LOG" 2>&1 || true
    fi
}

# Check if Homebrew is installed, install if not
if [[ ! -x "$BREW_PATH" ]]; then
    echo "$(date): Homebrew not found. Installing..." >> "$LOG"
    
    # Create Homebrew directory
    mkdir -p "$HOMEBREW_PREFIX"
    chown "$SERVICE_USER:staff" "$HOMEBREW_PREFIX"
    chmod 750 "$HOMEBREW_PREFIX"
    
    # Download and extract Homebrew
    echo "$(date): Downloading Homebrew..." >> "$LOG"
    curl -fsSL https://github.com/Homebrew/brew/tarball/master | \
        tar xz --strip-components=1 -C "$HOMEBREW_PREFIX"
    
    # Set ownership recursively
    chown -R "$SERVICE_USER:staff" "$HOMEBREW_PREFIX"
    chmod -R 750 "$HOMEBREW_PREFIX"
    
    # Verify installation
    if sudo -u "$SERVICE_USER" \
        HOME="$HOMEBREW_PREFIX" \
        HOMEBREW_CACHE="$HOMEBREW_CACHE_DIR" \
        HOMEBREW_LOGS="$HOMEBREW_LOGS_DIR" \
        HOMEBREW_TEMP="$HOMEBREW_TEMP_DIR" \
        HOMEBREW_NO_AUTO_UPDATE=1 \
        "$BREW_PATH" --version 2>&1 | sudo tee -a "$LOG" > /dev/null; then
        echo "$(date): Homebrew installed successfully" >> "$LOG"
    else
        echo "$(date): ERROR - Homebrew installation failed" >> "$LOG"
        exit 1
    fi
fi

# Set up CA certificates early (before any brew commands that might need SSL)
setup_ca_certificates

# ==============================================================================
# Function to run brew as service user with proper environment
# ==============================================================================
run_brew() {
    # Build XML_CATALOG_FILES path
    local XML_CATALOGS="$HOMEBREW_PREFIX/etc/xml/catalog"
    if [[ -f "/etc/xml/catalog" ]]; then
        XML_CATALOGS="$XML_CATALOGS:/etc/xml/catalog"
    fi
    
    # Get CA bundle
    local CA_BUNDLE
    CA_BUNDLE=$(get_ca_bundle)
    
    # Get ISRG Root X1 cert for Node.js
    local ISRG_CERT="$HOMEBREW_SSL_DIR/isrg-root-x1.pem"
    local NODE_CA_CERTS=""
    if [[ -f "$ISRG_CERT" ]]; then
        NODE_CA_CERTS="$ISRG_CERT"
    elif [[ -n "$CA_BUNDLE" ]]; then
        NODE_CA_CERTS="$CA_BUNDLE"
    fi
    
    # Build environment variables
    local ENV_VARS=(
        HOME="$HOMEBREW_PREFIX"
        HOMEBREW_CACHE="$HOMEBREW_CACHE_DIR"
        HOMEBREW_LOGS="$HOMEBREW_LOGS_DIR"
        HOMEBREW_TEMP="$HOMEBREW_TEMP_DIR"
        HOMEBREW_NO_AUTO_UPDATE=1
        HOMEBREW_NO_ENV_HINTS=1
        XML_CATALOG_FILES="$XML_CATALOGS"
        # Cask installs land in /Applications (system-wide) without re-quarantining.
        # Harmless for formula installs, which ignore cask opts.
        HOMEBREW_CASK_OPTS="--appdir=/Applications --no-quarantine"
    )
    
    # Add CA bundle if found
    if [[ -n "$CA_BUNDLE" ]]; then
        ENV_VARS+=(
            SSL_CERT_FILE="$CA_BUNDLE"
            SSL_CERT_DIR="$(dirname "$CA_BUNDLE")"
            REQUESTS_CA_BUNDLE="$CA_BUNDLE"
            CURL_CA_BUNDLE="$CA_BUNDLE"
        )
    fi
    
    # Add Node.js CA certs (critical for npm with Let's Encrypt certs)
    if [[ -n "$NODE_CA_CERTS" ]]; then
        ENV_VARS+=(
            NODE_EXTRA_CA_CERTS="$NODE_CA_CERTS"
        )
    fi
    
    sudo -u "$SERVICE_USER" "${ENV_VARS[@]}" "$BREW_PATH" "$@"
}

# Update Homebrew
echo "$(date): Updating Homebrew..." >> "$LOG"
run_brew update >> "$LOG" 2>&1 || echo "$(date): WARNING - brew update failed (continuing)" >> "$LOG"

# Verify Homebrew is functional
if ! run_brew --version >> "$LOG" 2>&1; then
    echo "$(date): ERROR - Homebrew is not functional after update. Is Deploy Homebrew policy installed first?" >> "$LOG"
    exit 1
fi

# Add tap if specified
if [[ -n "$TAP" ]]; then
    echo "$(date): Adding tap: $TAP" >> "$LOG"
    run_brew tap "$TAP" >> "$LOG" 2>&1 || echo "$(date): Tap may already exist" >> "$LOG"
fi

# Set up XML catalogs before installing
setup_xml_catalogs

# Check if package is already installed
if run_brew list $CASK_FLAG "$FORMULA" &>/dev/null; then
    echo "$(date): $FORMULA is already installed. Checking for updates..." >> "$LOG"
    run_brew upgrade $CASK_FLAG "$FORMULA" >> "$LOG" 2>&1 || echo "$(date): Already at latest version" >> "$LOG"
elif [[ $IS_CASK -eq 1 ]]; then
    # Casks are prebuilt .app/.pkg artifacts — no source build, so the docbook/XML
    # catalog and `brew postinstall` retries below don't apply.
    echo "$(date): Installing cask $FORMULA..." >> "$LOG"
    if ! run_brew install --cask "$FORMULA" >> "$LOG" 2>&1; then
        if run_brew list --cask "$FORMULA" &>/dev/null; then
            echo "$(date): WARNING - cask $FORMULA installed but with warnings" >> "$LOG"
        else
            echo "$(date): ERROR - Failed to install cask $FORMULA" >> "$LOG"
            exit 1
        fi
    fi
else
    echo "$(date): Installing $FORMULA..." >> "$LOG"
    if ! run_brew install "$FORMULA" >> "$LOG" 2>&1; then
        # Check if it installed despite post-install failure
        if run_brew list "$FORMULA" &>/dev/null; then
            echo "$(date): WARNING - $FORMULA installed but post-install had issues" >> "$LOG"
            run_brew postinstall "$FORMULA" >> "$LOG" 2>&1 || echo "$(date): Post-install retry also had issues (non-fatal)" >> "$LOG"
        else
            # Installation failed - try fixing docbook catalogs and retry
            echo "$(date): Initial install failed, attempting to fix XML catalogs and retry..." >> "$LOG"
            setup_xml_catalogs

            # A corrupt or partially-downloaded archive in Homebrew's cache makes
            # every subsequent `brew install` fail identically with a SHA256
            # mismatch, so a plain retry loops forever (observed fleet-wide on
            # "redpanda", whose formula/tap/release are all valid but which still
            # failed 23x/day on some devices). Purge just this formula's cached
            # download before retrying so brew re-fetches a clean copy. This only
            # touches the download archive, never an installed keg, and only runs
            # on the already-failed path, so it cannot regress a good install.
            CACHED_DL=$(run_brew --cache $CASK_FLAG "$FORMULA" 2>/dev/null)
            if [[ -n "$CACHED_DL" ]]; then
                echo "$(date): Purging cached download before retry: $CACHED_DL" >> "$LOG"
                rm -f "$CACHED_DL" "$CACHED_DL".incomplete "$CACHED_DL".* 2>/dev/null || true
            fi
            run_brew cleanup "$FORMULA" >> "$LOG" 2>&1 || true

            # Retry the installation
            echo "$(date): Retrying installation of $FORMULA..." >> "$LOG"
            if ! run_brew install "$FORMULA" >> "$LOG" 2>&1; then
                if run_brew list "$FORMULA" &>/dev/null; then
                    echo "$(date): WARNING - $FORMULA installed on retry but with warnings" >> "$LOG"
                else
                    echo "$(date): ERROR - Failed to install $FORMULA after retry" >> "$LOG"
                    exit 1
                fi
            fi
        fi
    fi
fi

# Verify installation
if run_brew list $CASK_FLAG "$FORMULA" &>/dev/null; then
    VERSION=$(run_brew info $CASK_FLAG "$FORMULA" --json=v2 2>/dev/null | grep -o '"installed":\[{"version":"[^"]*"' | head -1 | sed 's/.*"version":"//' | sed 's/".*//')
    echo "$(date): SUCCESS - $FORMULA installed (version: ${VERSION:-unknown})" >> "$LOG"
else
    echo "$(date): ERROR - Failed to install $FORMULA" >> "$LOG"
    exit 1
fi

# ==============================================================================
# Formula-specific post-processing
# ==============================================================================
formula_postprocess() {
    case "$FORMULA" in
        clickhouse)
            local BIN="$HOMEBREW_PREFIX/bin/clickhouse"
            local REAL="$HOMEBREW_PREFIX/bin/.clickhouse-bin"
            # ClickHouse's self-extracting binary builds its mkstemp template from
            # its own path, so it needs write access to the directory it lives in.
            # /opt/homebrew_srv/bin is owned by srv_mac (750), so regular users
            # get EACCES. Fix: wrap it to hard-link the binary into /tmp (writable)
            # and exec from there. Hard links are instant (no copy). Falls back to
            # cp if the filesystems differ. Re-wraps after brew upgrade.
            # Move real binary to .clickhouse-bin if BIN is not our /tmp wrapper.
            # Marker "_CACHE=" is unique to this wrapper — handles stale TMPDIR
            # wrappers from previous versions and post-brew-upgrade replacements.
            if [[ -x "$BIN" ]] && ! grep -q "_CACHE=" "$BIN" 2>/dev/null; then
                mv "$BIN" "$REAL"
                chown "$SERVICE_USER:staff" "$REAL"
                chmod 755 "$REAL"
            fi
            if [[ -f "$REAL" ]]; then
                cat > "$BIN" << 'WRAPEOF'
#!/bin/bash
_SRC="/opt/homebrew_srv/bin/.clickhouse-bin"
_KEY=$(stat -f '%i' "$_SRC" 2>/dev/null || echo 0)
_CACHE="/tmp/.clickhouse-${_KEY}"
if [[ ! -x "$_CACHE" ]]; then
    rm -f /tmp/.clickhouse-*
    ln "$_SRC" "$_CACHE" 2>/dev/null || cp "$_SRC" "$_CACHE"
    chmod 755 "$_CACHE"
fi
exec "$_CACHE" "$@"
WRAPEOF
                chown "$SERVICE_USER:staff" "$BIN"
                chmod 755 "$BIN"
                echo "$(date): Wrapped clickhouse to exec via /tmp hard link (mkstemp fix)" >> "$LOG"
            fi
            ;;
    esac
}

formula_postprocess

# ==============================================================================
# Configure keg-only formula paths
# Keg-only formulas aren't symlinked, so we need to add their bin dirs to PATH
# ==============================================================================
configure_keg_only_paths() {
    echo "$(date): Configuring keg-only formula paths..." >> "$LOG"
    
    local KEG_ONLY_PATHS_FILE="/etc/paths.d/homebrew_srv_keg_only"

    # Build list of installed keg-only formula bin paths
    local INSTALLED_KEG_PATHS=()
    for entry in "${KEG_ONLY_FORMULAS[@]}"; do
        local formula="${entry%%:*}"
        local bin_path="${entry##*:}"
        local full_path="$HOMEBREW_PREFIX/opt/$bin_path"
        
        # Check if this formula is installed and has a bin directory
        if run_brew list "$formula" &>/dev/null 2>&1 && [[ -d "$full_path" ]]; then
            INSTALLED_KEG_PATHS+=("$full_path")
            echo "$(date): Found keg-only formula with bin: $formula -> $full_path" >> "$LOG"
        fi
    done
    
    # Create/update /etc/paths.d file for keg-only formulas
    if [[ ${#INSTALLED_KEG_PATHS[@]} -gt 0 ]]; then
        # Check if file needs updating
        local NEW_CONTENT=""
        for path in "${INSTALLED_KEG_PATHS[@]}"; do
            NEW_CONTENT+="$path"$'\n'
        done
        
        local CURRENT_CONTENT=""
        if [[ -f "$KEG_ONLY_PATHS_FILE" ]]; then
            CURRENT_CONTENT=$(cat "$KEG_ONLY_PATHS_FILE")
        fi
        
        if [[ "$NEW_CONTENT" != "$CURRENT_CONTENT"$'\n' ]] && [[ "$NEW_CONTENT" != "$CURRENT_CONTENT" ]]; then
            printf "%s" "$NEW_CONTENT" > "$KEG_ONLY_PATHS_FILE"
            chmod 644 "$KEG_ONLY_PATHS_FILE"
            echo "$(date): Updated $KEG_ONLY_PATHS_FILE with keg-only paths" >> "$LOG"
        fi
    fi
    
    # Also add to user shell configs for immediate availability
    for USER_HOME in /Users/*; do
        if [[ -d "$USER_HOME" ]] && [[ "$USER_HOME" != "/Users/Shared" ]]; then
            local USERNAME
            USERNAME=$(basename "$USER_HOME")

            if ! id "$USERNAME" &>/dev/null; then
                continue
            fi
            
            local ZSHRC="$USER_HOME/.zshrc"
            
            # Add keg-only paths to .zshrc if not already present
            for path in "${INSTALLED_KEG_PATHS[@]}"; do
                if [[ -f "$ZSHRC" ]] && ! grep -q "$path" "$ZSHRC" 2>/dev/null; then
                    echo "" >> "$ZSHRC"
                    echo "# Keg-only formula: $(basename "$(dirname "$path")")" >> "$ZSHRC"
                    echo "export PATH=\"$path:\$PATH\"" >> "$ZSHRC"
                    chown "$USERNAME:staff" "$ZSHRC"
                    echo "$(date): Added $path to $ZSHRC" >> "$LOG"
                fi
            done
        fi
    done
}

# ==============================================================================
# Configure PATH for all users (idempotent - only adds if not present)
# ==============================================================================
echo "$(date): Configuring PATH for users..." >> "$LOG"

# Create /etc/paths.d entry for system-wide PATH (affects all users)
PATHS_FILE="/etc/paths.d/homebrew_srv"
if [[ ! -f "$PATHS_FILE" ]]; then
    echo "$HOMEBREW_PREFIX/bin" > "$PATHS_FILE"
    echo "$HOMEBREW_PREFIX/sbin" >> "$PATHS_FILE"
    chmod 644 "$PATHS_FILE"
    echo "$(date): Created $PATHS_FILE" >> "$LOG"
fi

# Add to /etc/profile.d for bash users
PROFILE_D="/etc/profile.d/homebrew_srv.sh"
if [[ ! -f "$PROFILE_D" ]]; then
    mkdir -p /etc/profile.d
    cat > "$PROFILE_D" << 'SHELLEOF'
# Example Homebrew PATH
export PATH="/opt/homebrew_srv/bin:/opt/homebrew_srv/sbin:$PATH"
SHELLEOF
    chmod 644 "$PROFILE_D"
    echo "$(date): Created $PROFILE_D" >> "$LOG"
fi

# Add to /etc/zprofile for zsh users (default shell on macOS)
ZPROFILE="/etc/zprofile"
if ! grep -q "homebrew_srv" "$ZPROFILE" 2>/dev/null; then
    cat >> "$ZPROFILE" << 'ZSHEOF'

# Example Homebrew PATH
export PATH="/opt/homebrew_srv/bin:/opt/homebrew_srv/sbin:$PATH"
ZSHEOF
    echo "$(date): Added Homebrew to $ZPROFILE" >> "$LOG"
fi

# Configure keg-only formula paths
configure_keg_only_paths

# ==============================================================================
# Configure shell-sourced tools (nvm, etc.) for all users
# ==============================================================================
configure_shell_tools() {
    local USER_HOME="$1"
    local USERNAME="$2"
    local ZSHRC="$USER_HOME/.zshrc"
    
    # NVM configuration
    if [[ -d "$HOMEBREW_PREFIX/opt/nvm" ]] && ! grep -q "NVM_DIR" "$ZSHRC" 2>/dev/null; then
        cat >> "$ZSHRC" << 'NVMEOF'

# NVM Configuration (managed by Example)
export NVM_DIR="/opt/homebrew_srv/opt/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/etc/bash_completion.d/nvm" ] && \. "$NVM_DIR/etc/bash_completion.d/nvm"
NVMEOF
        chown "$USERNAME:staff" "$ZSHRC"
        echo "$(date): Added NVM config to $ZSHRC" >> "$LOG"
    fi
}

# ==============================================================================
# Configure npm global prefix for each user (prevents EACCES permission errors)
# ==============================================================================
configure_npm_prefix() {
    local USER_HOME="$1"
    local USERNAME="$2"
    local NPM_GLOBAL_DIR="$USER_HOME/.npm-global"
    local ZSHRC="$USER_HOME/.zshrc"
    local NPMRC="$USER_HOME/.npmrc"
    
    # Check if node/npm is installed via our Homebrew
    if [[ ! -x "$HOMEBREW_PREFIX/bin/node" ]] && [[ ! -d "$HOMEBREW_PREFIX/opt/nvm" ]]; then
        return 0
    fi
    
    # Create user's npm global directory
    if [[ ! -d "$NPM_GLOBAL_DIR" ]]; then
        mkdir -p "$NPM_GLOBAL_DIR"
        chown "$USERNAME:staff" "$NPM_GLOBAL_DIR"
        chmod 755 "$NPM_GLOBAL_DIR"
        echo "$(date): Created npm global dir for $USERNAME" >> "$LOG"
    fi
    
    # Get CA bundle and ISRG cert for npmrc
    local CA_BUNDLE
    CA_BUNDLE=$(get_ca_bundle)
    
    # Set npm prefix and cafile via .npmrc (idempotent)
    if [[ ! -f "$NPMRC" ]]; then
        echo "prefix=$NPM_GLOBAL_DIR" > "$NPMRC"
        if [[ -n "$CA_BUNDLE" ]]; then
            echo "cafile=$CA_BUNDLE" >> "$NPMRC"
        fi
        chown "$USERNAME:staff" "$NPMRC"
        chmod 644 "$NPMRC"
        echo "$(date): Created $NPMRC with npm prefix and cafile" >> "$LOG"
    else
        if ! grep -q "^prefix=" "$NPMRC" 2>/dev/null; then
            echo "prefix=$NPM_GLOBAL_DIR" >> "$NPMRC"
        fi
        if [[ -n "$CA_BUNDLE" ]] && ! grep -q "^cafile=" "$NPMRC" 2>/dev/null; then
            echo "cafile=$CA_BUNDLE" >> "$NPMRC"
        fi
    fi
    
    # Add npm global bin to PATH in .zshrc (idempotent)
    if ! grep -q ".npm-global/bin" "$ZSHRC" 2>/dev/null; then
        cat >> "$ZSHRC" << 'NPMEOF'

# npm global packages (user-writable)
export PATH="$HOME/.npm-global/bin:$PATH"
NPMEOF
        chown "$USERNAME:staff" "$ZSHRC"
        echo "$(date): Added npm-global to PATH in $ZSHRC" >> "$LOG"
    fi
    
    # Also add to .bash_profile if it exists
    local BASH_PROFILE="$USER_HOME/.bash_profile"
    if [[ -f "$BASH_PROFILE" ]] && ! grep -q ".npm-global/bin" "$BASH_PROFILE" 2>/dev/null; then
        cat >> "$BASH_PROFILE" << 'NPMEOF'

# npm global packages (user-writable)
export PATH="$HOME/.npm-global/bin:$PATH"
NPMEOF
        echo "$(date): Added npm-global to PATH in $BASH_PROFILE" >> "$LOG"
    fi
}

# Add to each existing user's shell config (for interactive shells)
PATH_SNIPPET='
# Example Homebrew PATH
export PATH="/opt/homebrew_srv/bin:/opt/homebrew_srv/sbin:$PATH"'

for USER_HOME in /Users/*; do
    if [[ -d "$USER_HOME" ]] && [[ "$USER_HOME" != "/Users/Shared" ]]; then
        USERNAME=$(basename "$USER_HOME")
        
        # Skip if not a real user
        if ! id "$USERNAME" &>/dev/null; then
            continue
        fi
        
        # Add to .zshrc (zsh - default on macOS)
        ZSHRC="$USER_HOME/.zshrc"
        if [[ ! -f "$ZSHRC" ]]; then
            echo "$PATH_SNIPPET" > "$ZSHRC"
            chown "$USERNAME:staff" "$ZSHRC"
            chmod 644 "$ZSHRC"
            echo "$(date): Created $ZSHRC with Homebrew PATH" >> "$LOG"
        elif ! grep -q "homebrew_srv" "$ZSHRC" 2>/dev/null; then
            echo "$PATH_SNIPPET" >> "$ZSHRC"
            echo "$(date): Added Homebrew to $ZSHRC" >> "$LOG"
        fi
        
        # Configure shell-sourced tools (nvm, etc.)
        configure_shell_tools "$USER_HOME" "$USERNAME"
        
        # Configure npm global prefix
        configure_npm_prefix "$USER_HOME" "$USERNAME"
        
        # Add to .bash_profile if it exists (for bash users)
        BASH_PROFILE="$USER_HOME/.bash_profile"
        if [[ -f "$BASH_PROFILE" ]] && ! grep -q "homebrew_srv" "$BASH_PROFILE" 2>/dev/null; then
            echo "$PATH_SNIPPET" >> "$BASH_PROFILE"
            echo "$(date): Added Homebrew to $BASH_PROFILE" >> "$LOG"
        fi
    fi
done

echo "$(date): PATH configuration complete" >> "$LOG"

# Remove Gatekeeper quarantine from all Homebrew-installed binaries.
# Binaries downloaded from GitHub/CDN get com.apple.quarantine set, which
# causes macOS to block execution with an "unverified developer" prompt.
echo "$(date): Removing quarantine attributes from $HOMEBREW_PREFIX..." >> "$LOG"
xattr -dr com.apple.quarantine "$HOMEBREW_PREFIX" 2>/dev/null || true
echo "$(date): Quarantine removal complete" >> "$LOG"

echo "============================================" >> "$LOG"

exit 0