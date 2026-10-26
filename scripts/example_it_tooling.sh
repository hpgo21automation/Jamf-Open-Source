#!/bin/bash
# ==============================================================================
# Example IT Tooling Installer
# ==============================================================================
# Installs all developer CLI tools via Homebrew for srv_mac user
# ==============================================================================

set -euo pipefail

# Variables
SERVICE_USER="srv_mac"
HOMEBREW_PREFIX="/opt/homebrew_srv"
BREW_PATH="$HOMEBREW_PREFIX/bin/brew"
HOMEBREW_CACHE_DIR="$HOMEBREW_PREFIX/cache"
HOMEBREW_LOGS_DIR="$HOMEBREW_PREFIX/logs"
HOMEBREW_TEMP_DIR="$HOMEBREW_PREFIX/tmp"
HOMEBREW_SSL_DIR="$HOMEBREW_PREFIX/etc/ssl/certs"
LOG="/var/log/example_it_tooling.log"

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
echo "============================================" >> "$LOG"
echo "$(date): Example IT Tooling Installer" >> "$LOG"
echo "============================================" >> "$LOG"

# Check if srv_mac exists
if ! id "$SERVICE_USER" &>/dev/null; then
    echo "$(date): ERROR - User $SERVICE_USER does not exist" >> "$LOG"
    exit 1
fi

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

# Check and install/update Xcode Command Line Tools (required by Homebrew to build packages)
if clt_needs_install; then
    echo "$(date): Xcode CLT missing or outdated (installed: $(clt_installed_version || true), macOS: $(sw_vers -productVersion)). Installing..." >> "$LOG"
    echo "Xcode CLT missing or outdated - attempting install..."

    # Method 1: softwareupdate with placeholder trigger
    PLACEHOLDER="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
    touch "$PLACEHOLDER"
    sleep 3
    echo "Checking softwareupdate catalog..."
    SWUPDATE_OUT=$(softwareupdate -l 2>&1) || true
    echo "$SWUPDATE_OUT" | head -20
    # Placeholder stays alive until after install — removing it before causes "No such update"

    CLT_PACKAGE=""
    CLT_PACKAGE=$(echo "$SWUPDATE_OUT" | grep -E "Label:.*Command Line" | sed 's/^.*Label: //' | head -n 1 | xargs) || true
    if [[ -z "$CLT_PACKAGE" ]]; then
        CLT_PACKAGE=$(echo "$SWUPDATE_OUT" | grep -oE "Command Line Tools for Xcode-[0-9.]+" | head -n 1) || true
    fi

    if [[ -n "$CLT_PACKAGE" ]]; then
        echo "Found package: $CLT_PACKAGE"
        echo "$(date): Installing $CLT_PACKAGE (keeping placeholder alive during install)..." >> "$LOG"
        INSTALL_RESULT=0
        # Keep placeholder alive — removing it before install causes "No such update"
        softwareupdate -i "$CLT_PACKAGE" --agree-to-license --verbose 2>&1 | tee -a "$LOG" || INSTALL_RESULT=$?

        # macOS 26+: label is "Product OS_VER-PKG_VER" but installer needs "Product-PKG_VER"
        if [[ $INSTALL_RESULT -ne 0 ]]; then
            BASE=$(echo "$CLT_PACKAGE" | sed 's/[[:space:]][0-9][0-9.]*-[0-9].*//')
            VER=$(echo "$CLT_PACKAGE" | grep -oE '[0-9][0-9.]*$')
            ALT="${BASE}-${VER}"
            if [[ -n "$VER" ]] && [[ "$ALT" != "$CLT_PACKAGE" ]]; then
                echo "Retrying with alternate identifier: $ALT"
                echo "$(date): Retrying with $ALT" >> "$LOG"
                softwareupdate -i "$ALT" --agree-to-license --verbose 2>&1 | tee -a "$LOG" || true
            fi
        fi
    else
        echo "WARNING: No CLT package found in softwareupdate catalog"
        echo "$(date): WARNING - softwareupdate catalog output:" >> "$LOG"
        echo "$SWUPDATE_OUT" >> "$LOG"
    fi

    # Placeholder no longer needed — remove after all install attempts
    rm -f "$PLACEHOLDER"

    # Method 2: configure existing directory if present
    if [[ -d "/Library/Developer/CommandLineTools" ]]; then
        echo "Found /Library/Developer/CommandLineTools - configuring..."
        xcode-select --switch /Library/Developer/CommandLineTools 2>/dev/null || true
    fi

    # Method 3: trigger via xcode-select --install and wait up to 5 min
    if ! xcode-select -p &>/dev/null; then
        echo "Method 3: triggering xcode-select --install (waiting up to 5 min)..."
        xcode-select --install 2>/dev/null || true
        for _ in {1..60}; do
            sleep 5
            if [[ -d "/Library/Developer/CommandLineTools/usr/bin/git" ]]; then
                xcode-select --switch /Library/Developer/CommandLineTools 2>/dev/null || true
                break
            fi
        done
    fi

    if clt_needs_install; then
        echo "$(date): ERROR - Xcode CLT installation failed" >> "$LOG"
        echo "ERROR: All CLT install methods failed. Manual install may be required."
        echo "CLT is missing or too outdated for macOS $(sw_vers -productVersion) (installed: $(clt_installed_version || true))."
        echo "Try: System Settings > General > Software Update, or run the 'Install xcode CLI tools' policy."
        exit 1
    fi
    echo "$(date): Xcode CLT $(clt_installed_version) ready at $(xcode-select -p)" >> "$LOG"
    echo "Xcode CLT $(clt_installed_version) ready at $(xcode-select -p)"
fi

# Create required directories
for DIR in "$HOMEBREW_CACHE_DIR" "$HOMEBREW_LOGS_DIR" "$HOMEBREW_TEMP_DIR" "$HOMEBREW_SSL_DIR"; do
    if [[ ! -d "$DIR" ]]; then
        mkdir -p "$DIR"
        echo "$(date): Created $DIR" >> "$LOG"
    fi
done
# mkdir -p creates intermediate dirs (e.g. /opt/homebrew_srv/etc) as root.
# Fix ownership of the entire prefix so srv_mac can write everywhere.
chown -R "$SERVICE_USER:staff" "$HOMEBREW_PREFIX"

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
    
    if [[ ! -d "/etc/xml" ]]; then
        mkdir -p /etc/xml
    fi
    chmod 775 /etc/xml 2>/dev/null || true
    chgrp staff /etc/xml 2>/dev/null || true
    
    if [[ ! -d "$HOMEBREW_PREFIX/etc/xml" ]]; then
        mkdir -p "$HOMEBREW_PREFIX/etc/xml"
        chown "$SERVICE_USER:staff" "$HOMEBREW_PREFIX/etc/xml"
        chmod 755 "$HOMEBREW_PREFIX/etc/xml"
    fi
    
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
    
    if run_brew list docbook &>/dev/null 2>&1; then
        echo "$(date): Running docbook postinstall..." >> "$LOG"
        run_brew postinstall docbook >> "$LOG" 2>&1 || true
    fi
    
    if run_brew list docbook-xsl &>/dev/null 2>&1; then
        echo "$(date): Running docbook-xsl postinstall..." >> "$LOG"
        run_brew postinstall docbook-xsl >> "$LOG" 2>&1 || true
    fi
}

# ==============================================================================
# Function to run brew as service user with proper environment
# ==============================================================================
run_brew() {
    local XML_CATALOGS="$HOMEBREW_PREFIX/etc/xml/catalog"
    if [[ -f "/etc/xml/catalog" ]]; then
        XML_CATALOGS="$XML_CATALOGS:/etc/xml/catalog"
    fi
    
    local CA_BUNDLE
    CA_BUNDLE=$(get_ca_bundle)
    
    local ISRG_CERT="$HOMEBREW_SSL_DIR/isrg-root-x1.pem"
    local NODE_CA_CERTS=""
    if [[ -f "$ISRG_CERT" ]]; then
        NODE_CA_CERTS="$ISRG_CERT"
    elif [[ -n "$CA_BUNDLE" ]]; then
        NODE_CA_CERTS="$CA_BUNDLE"
    fi
    
    local ENV_VARS=(
        HOME="$HOMEBREW_PREFIX"
        HOMEBREW_CACHE="$HOMEBREW_CACHE_DIR"
        HOMEBREW_LOGS="$HOMEBREW_LOGS_DIR"
        HOMEBREW_TEMP="$HOMEBREW_TEMP_DIR"
        HOMEBREW_NO_AUTO_UPDATE=1
        HOMEBREW_NO_ANALYTICS=1
        HOMEBREW_NO_ENV_HINTS=1
        XML_CATALOG_FILES="$XML_CATALOGS"
    )
    
    if [[ -n "$CA_BUNDLE" ]]; then
        ENV_VARS+=(
            SSL_CERT_FILE="$CA_BUNDLE"
            SSL_CERT_DIR="$(dirname "$CA_BUNDLE")"
            REQUESTS_CA_BUNDLE="$CA_BUNDLE"
            CURL_CA_BUNDLE="$CA_BUNDLE"
        )
    fi
    
    if [[ -n "$NODE_CA_CERTS" ]]; then
        ENV_VARS+=(
            NODE_EXTRA_CA_CERTS="$NODE_CA_CERTS"
        )
    fi
    
    sudo -u "$SERVICE_USER" "${ENV_VARS[@]}" "$BREW_PATH" "$@"
}

# ==============================================================================
# Function to run npm as service user with proper environment
# ==============================================================================
run_npm() {
    local NPM_PATH="$HOMEBREW_PREFIX/bin/npm"
    
    if [[ ! -x "$NPM_PATH" ]]; then
        echo "$(date): ERROR - npm not found at $NPM_PATH" >> "$LOG"
        return 1
    fi
    
    local CA_BUNDLE
    CA_BUNDLE=$(get_ca_bundle)
    
    local ISRG_CERT="$HOMEBREW_SSL_DIR/isrg-root-x1.pem"
    local NODE_CA_CERTS=""
    if [[ -f "$ISRG_CERT" ]]; then
        NODE_CA_CERTS="$ISRG_CERT"
    elif [[ -n "$CA_BUNDLE" ]]; then
        NODE_CA_CERTS="$CA_BUNDLE"
    fi
    
    local ENV_VARS=(
        HOME="$HOMEBREW_PREFIX"
        PATH="$HOMEBREW_PREFIX/bin:$PATH"
        NPM_CONFIG_PREFIX="$HOMEBREW_PREFIX"
        NPM_CONFIG_CACHE="$HOMEBREW_CACHE_DIR/npm"
    )
    
    if [[ -n "$CA_BUNDLE" ]]; then
        ENV_VARS+=(
            SSL_CERT_FILE="$CA_BUNDLE"
            NPM_CONFIG_CAFILE="$CA_BUNDLE"
        )
    fi
    
    if [[ -n "$NODE_CA_CERTS" ]]; then
        ENV_VARS+=(
            NODE_EXTRA_CA_CERTS="$NODE_CA_CERTS"
        )
    fi
    
    sudo -u "$SERVICE_USER" "${ENV_VARS[@]}" "$NPM_PATH" "$@"
}

# Check if Homebrew is installed, install if not
if [[ ! -x "$BREW_PATH" ]]; then
    echo "$(date): Homebrew not found. Installing..." >> "$LOG"

    mkdir -p "$HOMEBREW_PREFIX"
    chown "$SERVICE_USER:staff" "$HOMEBREW_PREFIX"
    chmod 750 "$HOMEBREW_PREFIX"

    echo "$(date): Downloading Homebrew tarball from GitHub..." >> "$LOG"
    if ! curl -fsSL https://github.com/Homebrew/brew/tarball/master | \
        tar xz --strip-components=1 -C "$HOMEBREW_PREFIX"; then
        echo "$(date): ERROR - Failed to download or extract Homebrew tarball" >> "$LOG"
        exit 1
    fi

    chown -R "$SERVICE_USER:staff" "$HOMEBREW_PREFIX"
    chmod -R 750 "$HOMEBREW_PREFIX"

    # Verify with minimal env (CA certs not set up yet)
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

# Set up CA certificates early (needed for SSL operations)
setup_ca_certificates

# Update Homebrew
echo "$(date): Updating Homebrew..." >> "$LOG"
run_brew update >> "$LOG" 2>&1 || echo "$(date): WARNING - brew update failed (continuing)" >> "$LOG"

# Verify Homebrew is functional before attempting package installs
echo "$(date): Verifying Homebrew is operational..." >> "$LOG"
if ! run_brew --version >> "$LOG" 2>&1; then
    echo "$(date): ERROR - Homebrew is not functional after update. Exiting." >> "$LOG"
    exit 1
fi

# Verify formula database is populated (fails on fresh tarball install if brew update didn't run)
echo "$(date): Verifying formula database..." >> "$LOG"
FORMULA_TEST_OUTPUT=$(run_brew info git 2>&1) || true
if ! echo "$FORMULA_TEST_OUTPUT" | grep -q "git:"; then
    echo "$(date): ERROR - Formula database empty or unavailable. brew update output:" >> "$LOG"
    echo "$FORMULA_TEST_OUTPUT" >> "$LOG"
    echo "ERROR: Homebrew formula database is not populated."
    echo "brew info git returned:"
    echo "$FORMULA_TEST_OUTPUT" | head -10
    echo "This usually means brew update failed. Check network/SSL and re-run."
    exit 1
fi
echo "$(date): Formula database OK" >> "$LOG"

# Set up XML catalogs
setup_xml_catalogs

# Add required taps
echo "$(date): Adding taps..." >> "$LOG"
run_brew tap oven-sh/bun >> "$LOG" 2>&1 || true
run_brew tap bufbuild/buf >> "$LOG" 2>&1 || true
run_brew tap jetstack/tap >> "$LOG" 2>&1 || true

# ==============================================================================
# Package Definitions
# ==============================================================================
BREW_PACKAGES=(
    # Cloud & Infrastructure
    "mongodb-atlas-cli"
    "cloud-sql-proxy"
    "opentofu"
    
    # Kubernetes
    "cmctl"
    "helm"
    "helmfile"
    "k6"
    "kubectl"
    "kubectx"
    "kube-ps1"
    "kustomize"
    
    # Native Libraries (required by WeasyPrint and other tools)
    "cairo"
    "glib"
    "pango"

    # Databases
    "clickhouse"
    "dbmate"
    "mongosh"
    "libpq"            # PostgreSQL client (psql) - keg-only
    
    # Languages & Runtimes
    "bun"
    "go"
    "golangci-lint"
    "micromamba"
    "node"
    "nvm"
    "rust"
    "rustup"
    "uv"
    
    # Dev Tools
    "buf"
    "delve"
    "gomplate"
    "grpcurl"
    "jira-cli"
    
    # Networking
    "haproxy"
    "socat"
)

GCLOUD_COMPONENTS=(
    "alpha"
    "anthos-auth"
    "app-engine-go"
    "app-engine-python"
    "app-engine-python-extras"
    "beta"
    "bigtable"
    "cbt"
    "cloud-datastore-emulator"
    "cloud-firestore-emulator"
    "cloud-run-proxy"
    "cloud-sql-proxy"
    "config-connector"
    "docker-credential-gcr"
    "enterprise-certificate-proxy"
    "gke-gcloud-auth-plugin"
    "istioctl"
    "kpt"
    "kubectl"
    "kubectl-oidc"
    "kustomize"
    "local-extract"
    "log-streaming"
    "minikube"
    "nomos"
    "package-go-module"
    "pkg"
    "pubsub-emulator"
    "skaffold"
    "spanner-cli"
    "terraform-tools"
)

# ==============================================================================
# Install Homebrew Packages
# ==============================================================================
FAILED_PACKAGES=()
INSTALLED_PACKAGES=()
FIRST_FAILURE_OUTPUT=""

install_package() {
    local PACKAGE="$1"
    echo "$(date): Installing $PACKAGE..." >> "$LOG"
    
    INSTALL_OUTPUT=$(run_brew install "$PACKAGE" 2>&1) || true
    echo "$INSTALL_OUTPUT" >> "$LOG"
    
    if run_brew list "$PACKAGE" &>/dev/null; then
        INSTALLED_PACKAGES+=("$PACKAGE")
        echo "$(date): SUCCESS - $PACKAGE installed" >> "$LOG"
        return 0
    fi
    
    if run_brew list --cask "$PACKAGE" &>/dev/null; then
        INSTALLED_PACKAGES+=("$PACKAGE")
        echo "$(date): SUCCESS - $PACKAGE installed (cask)" >> "$LOG"
        return 0
    fi
    
    # Retry on network/SSL errors
    if echo "$INSTALL_OUTPUT" | grep -qiE "(SSL|certificate|curl.*failed|fetch.*failed|Connection reset|timed out|ECONNRESET|ETIMEDOUT|Could not resolve|unable to connect)"; then
        echo "$(date): Network/SSL issue detected for $PACKAGE, waiting 10s and retrying..." >> "$LOG"
        sleep 10
        INSTALL_OUTPUT=$(run_brew install "$PACKAGE" 2>&1) || true
        echo "$INSTALL_OUTPUT" >> "$LOG"
        if run_brew list "$PACKAGE" &>/dev/null; then
            INSTALLED_PACKAGES+=("$PACKAGE")
            echo "$(date): SUCCESS - $PACKAGE installed on network retry" >> "$LOG"
            return 0
        fi
    fi

    # Retry on XML catalog issues
    if echo "$INSTALL_OUTPUT" | grep -q -E "(docbook|catalog|xml|sgml|Entity.*not defined)" ; then
        echo "$(date): Detected possible XML catalog issue, retrying..." >> "$LOG"
        setup_xml_catalogs

        INSTALL_OUTPUT=$(run_brew install "$PACKAGE" 2>&1) || true
        echo "$INSTALL_OUTPUT" >> "$LOG"

        if run_brew list "$PACKAGE" &>/dev/null; then
            INSTALLED_PACKAGES+=("$PACKAGE")
            echo "$(date): SUCCESS - $PACKAGE installed on retry" >> "$LOG"
            return 0
        fi
    fi

    FAILED_PACKAGES+=("$PACKAGE")
    echo "$(date): FAILED - $PACKAGE not installed" >> "$LOG"
    if [[ -z "$FIRST_FAILURE_OUTPUT" ]]; then
        FIRST_FAILURE_OUTPUT=$(echo "$INSTALL_OUTPUT" | head -8)
    fi
    return 1
}

for PACKAGE in "${BREW_PACKAGES[@]}"; do
    install_package "$PACKAGE" || true
done

# ==============================================================================
# Install Google Cloud SDK Components
# ==============================================================================
echo "$(date): Installing Google Cloud SDK components..." >> "$LOG"

GCLOUD_SDK_DIR="/usr/local/google-cloud-sdk"
GCLOUD_BIN="$GCLOUD_SDK_DIR/bin/gcloud"
FAILED_GCLOUD_COMPONENTS=()
INSTALLED_GCLOUD_COMPONENTS=()
GCLOUD_SDK_FOUND=false

if [[ -x "$GCLOUD_BIN" ]]; then
    echo "$(date): Found gcloud at $GCLOUD_BIN" >> "$LOG"
    GCLOUD_SDK_FOUND=true
elif command -v gcloud &>/dev/null; then
    GCLOUD_BIN=$(command -v gcloud)
    GCLOUD_SDK_DIR=$(dirname "$(dirname "$GCLOUD_BIN")")
    echo "$(date): Found gcloud at $GCLOUD_BIN (SDK: $GCLOUD_SDK_DIR)" >> "$LOG"
    GCLOUD_SDK_FOUND=true
else
    echo "$(date): WARNING - Google Cloud SDK not found; skipping component installation" >> "$LOG"
    echo "$(date): Run 'Install Google Cloud CLI (with setup)' policy first if gcloud components are needed" >> "$LOG"
    GCLOUD_BIN=""
fi

if [[ "$GCLOUD_SDK_FOUND" == "true" ]]; then
    chmod -R 775 "$GCLOUD_SDK_DIR" 2>/dev/null || true
    chgrp -R admin "$GCLOUD_SDK_DIR" 2>/dev/null || true
    
    EXISTING_COMPONENTS=$("$GCLOUD_BIN" components list --filter="state.name=Installed" --format="value(id)" 2>/dev/null || echo "")
    
    for COMPONENT in "${GCLOUD_COMPONENTS[@]}"; do
        if echo "$EXISTING_COMPONENTS" | grep -q "^${COMPONENT}$"; then
            INSTALLED_GCLOUD_COMPONENTS+=("$COMPONENT")
            echo "$(date): SKIP - $COMPONENT already installed" >> "$LOG"
            continue
        fi
        
        echo "$(date): Installing gcloud component: $COMPONENT..." >> "$LOG"
        
        if "$GCLOUD_BIN" components install "$COMPONENT" --quiet >> "$LOG" 2>&1; then
            INSTALLED_GCLOUD_COMPONENTS+=("$COMPONENT")
            echo "$(date): SUCCESS - gcloud component $COMPONENT installed" >> "$LOG"
        else
            FAILED_GCLOUD_COMPONENTS+=("$COMPONENT")
            echo "$(date): FAILED - gcloud component $COMPONENT not installed" >> "$LOG"
        fi
    done
    
    chmod -R 775 "$GCLOUD_SDK_DIR" 2>/dev/null || true
    chgrp -R admin "$GCLOUD_SDK_DIR" 2>/dev/null || true
    
    for tool in kubectl minikube skaffold kustomize istioctl kpt nomos cbt docker-credential-gcr; do
        if [[ -x "$GCLOUD_SDK_DIR/bin/$tool" ]]; then
            if [[ ! -e "/usr/local/bin/$tool" ]] || [[ -L "/usr/local/bin/$tool" ]]; then
                ln -sf "$GCLOUD_SDK_DIR/bin/$tool" "/usr/local/bin/$tool"
                echo "$(date): Symlink created: /usr/local/bin/$tool" >> "$LOG"
            fi
        fi
    done
else
    echo "$(date): SKIPPED - gcloud component installation (SDK not installed)" >> "$LOG"
fi

# ==============================================================================
# Install npm packages
# ==============================================================================
echo "$(date): Installing npm packages..." >> "$LOG"

# Create npm cache directory
if [[ ! -d "$HOMEBREW_CACHE_DIR/npm" ]]; then
    mkdir -p "$HOMEBREW_CACHE_DIR/npm"
    chown "$SERVICE_USER:staff" "$HOMEBREW_CACHE_DIR/npm"
    chmod 750 "$HOMEBREW_CACHE_DIR/npm"
fi

if [[ -x "$HOMEBREW_PREFIX/bin/npm" ]]; then
    echo "$(date): Installing auth0-cli via npm..." >> "$LOG"
    
    if run_npm install -g auth0-cli >> "$LOG" 2>&1; then
        INSTALLED_PACKAGES+=("auth0-cli")
        echo "$(date): SUCCESS - auth0-cli installed" >> "$LOG"
    else
        echo "$(date): Retrying auth0-cli with strict-ssl=false..." >> "$LOG"
        if run_npm install -g auth0-cli --strict-ssl=false >> "$LOG" 2>&1; then
            INSTALLED_PACKAGES+=("auth0-cli")
            echo "$(date): SUCCESS - auth0-cli installed (with strict-ssl=false)" >> "$LOG"
        else
            FAILED_PACKAGES+=("auth0-cli")
            echo "$(date): FAILED - auth0-cli not installed" >> "$LOG"
        fi
    fi
else
    echo "$(date): SKIPPED - auth0-cli (npm not found)" >> "$LOG"
fi

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
            
            # Ensure .zshrc exists
            if [[ ! -f "$ZSHRC" ]]; then
                touch "$ZSHRC"
                chown "$USERNAME:staff" "$ZSHRC"
                chmod 644 "$ZSHRC"
            fi
            
            # Add keg-only paths to .zshrc if not already present
            for path in "${INSTALLED_KEG_PATHS[@]+"${INSTALLED_KEG_PATHS[@]}"}"; do
                if ! grep -q "$path" "$ZSHRC" 2>/dev/null; then
                    local formula_name; formula_name=$(basename "$(dirname "$path")")
                    echo "" >> "$ZSHRC"
                    echo "# Keg-only formula: $formula_name" >> "$ZSHRC"
                    echo "export PATH=\"$path:\$PATH\"" >> "$ZSHRC"
                    chown "$USERNAME:staff" "$ZSHRC"
                    echo "$(date): Added $path to $ZSHRC" >> "$LOG"
                fi
            done
        fi
    done
}

# ==============================================================================
# Configure PATH for all users
# ==============================================================================
echo "$(date): Configuring PATH for all users..." >> "$LOG"

PATHS_FILE="/etc/paths.d/homebrew_srv"
if [[ ! -f "$PATHS_FILE" ]]; then
    echo "$HOMEBREW_PREFIX/bin" > "$PATHS_FILE"
    echo "$HOMEBREW_PREFIX/sbin" >> "$PATHS_FILE"
    chmod 644 "$PATHS_FILE"
    echo "$(date): Created $PATHS_FILE" >> "$LOG"
fi

PROFILE_D="/etc/profile.d/homebrew_srv.sh"
if [[ ! -f "$PROFILE_D" ]]; then
    mkdir -p /etc/profile.d
    cat > "$PROFILE_D" << 'SHELLEOF'
# Example Homebrew PATH
export PATH="/opt/homebrew_srv/bin:/opt/homebrew_srv/sbin:$PATH"
export DYLD_FALLBACK_LIBRARY_PATH="/opt/homebrew_srv/lib:$DYLD_FALLBACK_LIBRARY_PATH"
SHELLEOF
    chmod 644 "$PROFILE_D"
    echo "$(date): Created $PROFILE_D" >> "$LOG"
fi

ZPROFILE="/etc/zprofile"
if ! grep -q "homebrew_srv" "$ZPROFILE" 2>/dev/null; then
    cat >> "$ZPROFILE" << 'ZSHEOF'

# Example Homebrew PATH
export PATH="/opt/homebrew_srv/bin:/opt/homebrew_srv/sbin:$PATH"
export DYLD_FALLBACK_LIBRARY_PATH="/opt/homebrew_srv/lib:$DYLD_FALLBACK_LIBRARY_PATH"
ZSHEOF
    echo "$(date): Added Homebrew to $ZPROFILE" >> "$LOG"
fi

# Configure keg-only formula paths (like libpq/psql)
configure_keg_only_paths

# ==============================================================================
# Configure user shell configs
# ==============================================================================
configure_shell_tools() {
    local USER_HOME="$1"
    local USERNAME="$2"
    local ZSHRC="$USER_HOME/.zshrc"
    local BASH_PROFILE="$USER_HOME/.bash_profile"
    
    if [[ -d "$HOMEBREW_PREFIX/opt/nvm" ]]; then
        if [[ ! -f "$ZSHRC" ]]; then
            touch "$ZSHRC"
            chown "$USERNAME:staff" "$ZSHRC"
            chmod 644 "$ZSHRC"
        fi
        
        if ! grep -q "NVM_DIR" "$ZSHRC" 2>/dev/null; then
            cat >> "$ZSHRC" << 'NVMEOF'

# NVM Configuration (managed by Example)
export NVM_DIR="/opt/homebrew_srv/opt/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/etc/bash_completion.d/nvm" ] && \. "$NVM_DIR/etc/bash_completion.d/nvm"
NVMEOF
            chown "$USERNAME:staff" "$ZSHRC"
            echo "$(date): Added NVM config to $ZSHRC" >> "$LOG"
        fi
        
        if [[ -f "$BASH_PROFILE" ]] && ! grep -q "NVM_DIR" "$BASH_PROFILE" 2>/dev/null; then
            cat >> "$BASH_PROFILE" << 'NVMBASHEOF'

# NVM Configuration (managed by Example)
export NVM_DIR="/opt/homebrew_srv/opt/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
NVMBASHEOF
            chown "$USERNAME:staff" "$BASH_PROFILE"
            echo "$(date): Added NVM config to $BASH_PROFILE" >> "$LOG"
        fi
    fi
}

for USER_HOME in /Users/*; do
    if [[ -d "$USER_HOME" ]] && [[ "$USER_HOME" != "/Users/Shared" ]]; then
        USERNAME=$(basename "$USER_HOME")
        
        if ! id "$USERNAME" &>/dev/null; then
            continue
        fi
        
        ZSHRC="$USER_HOME/.zshrc"
        if [[ -f "$ZSHRC" ]] && ! grep -q "homebrew_srv" "$ZSHRC" 2>/dev/null; then
            cat >> "$ZSHRC" << 'ZSHRCEOF'

# Example Homebrew PATH
export PATH="/opt/homebrew_srv/bin:/opt/homebrew_srv/sbin:$PATH"
export DYLD_FALLBACK_LIBRARY_PATH="/opt/homebrew_srv/lib:$DYLD_FALLBACK_LIBRARY_PATH"
ZSHRCEOF
            chown "$USERNAME:staff" "$ZSHRC"
            echo "$(date): Added Homebrew to $ZSHRC" >> "$LOG"
        elif [[ ! -f "$ZSHRC" ]]; then
            cat > "$ZSHRC" << 'ZSHRCEOF'
# Example Homebrew PATH
export PATH="/opt/homebrew_srv/bin:/opt/homebrew_srv/sbin:$PATH"
export DYLD_FALLBACK_LIBRARY_PATH="/opt/homebrew_srv/lib:$DYLD_FALLBACK_LIBRARY_PATH"
ZSHRCEOF
            chown "$USERNAME:staff" "$ZSHRC"
            chmod 644 "$ZSHRC"
            echo "$(date): Created $ZSHRC with Homebrew PATH" >> "$LOG"
        fi
        
        configure_shell_tools "$USER_HOME" "$USERNAME"
        
        BASH_PROFILE="$USER_HOME/.bash_profile"
        if [[ -f "$BASH_PROFILE" ]] && ! grep -q "homebrew_srv" "$BASH_PROFILE" 2>/dev/null; then
            cat >> "$BASH_PROFILE" << 'BASHEOF'

# Example Homebrew PATH
export PATH="/opt/homebrew_srv/bin:/opt/homebrew_srv/sbin:$PATH"
BASHEOF
            chown "$USERNAME:staff" "$BASH_PROFILE"
            echo "$(date): Added Homebrew to $BASH_PROFILE" >> "$LOG"
        fi
    fi
done

# ==============================================================================
# Summary
# ==============================================================================
echo "============================================" >> "$LOG"
echo "$(date): Installation Summary" >> "$LOG"
echo "============================================" >> "$LOG"
echo "Installed Homebrew packages: ${#INSTALLED_PACKAGES[@]}" >> "$LOG"
echo "Failed Homebrew packages: ${#FAILED_PACKAGES[@]}" >> "$LOG"
if [[ ${#FAILED_PACKAGES[@]} -gt 0 ]]; then
    echo "Failed: ${FAILED_PACKAGES[*]}" >> "$LOG"
fi
if [[ "$GCLOUD_SDK_FOUND" == "true" ]]; then
    echo "Installed gcloud components: ${#INSTALLED_GCLOUD_COMPONENTS[@]}" >> "$LOG"
    echo "Failed gcloud components: ${#FAILED_GCLOUD_COMPONENTS[@]}" >> "$LOG"
    if [[ ${#FAILED_GCLOUD_COMPONENTS[@]} -gt 0 ]]; then
        echo "Failed: ${FAILED_GCLOUD_COMPONENTS[*]}" >> "$LOG"
    fi
else
    echo "Google Cloud SDK: not installed (skipped)" >> "$LOG"
fi
echo "============================================" >> "$LOG"

echo ""
echo "============================================"
echo "Installation Complete"
echo "============================================"
echo ""
echo "Homebrew Packages: ${#INSTALLED_PACKAGES[@]} installed, ${#FAILED_PACKAGES[@]} failed"
if [[ "$GCLOUD_SDK_FOUND" == "true" ]]; then
    echo "Google Cloud SDK: ${#INSTALLED_GCLOUD_COMPONENTS[@]} installed, ${#FAILED_GCLOUD_COMPONENTS[@]} failed"
else
    echo "Google Cloud SDK: not installed (run 'Install Google Cloud CLI' policy first)"
fi
echo ""
if [[ ${#FAILED_PACKAGES[@]} -gt 0 ]]; then
    echo "Failed Homebrew packages: ${FAILED_PACKAGES[*]}"
    if [[ -n "$FIRST_FAILURE_OUTPUT" ]]; then
        echo ""
        echo "First failure (${FAILED_PACKAGES[0]}) brew output:"
        echo "$FIRST_FAILURE_OUTPUT"
    fi
fi
if [[ ${#FAILED_GCLOUD_COMPONENTS[@]} -gt 0 ]]; then
    echo "Failed gcloud components: ${FAILED_GCLOUD_COMPONENTS[*]}"
fi
echo ""
echo "Full log: $LOG"
echo "============================================"

exit 0