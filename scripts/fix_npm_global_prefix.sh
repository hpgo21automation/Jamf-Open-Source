#!/bin/bash
# Configure npm global prefix for the logged-in user
# Prevents EACCES errors when running 'npm install -g' as a standard user
# by redirecting global installs to ~/.npm-global instead of /opt/homebrew_srv
# Also fixes gcloud config ownership and installs common global packages

CONSOLE_USER=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')

if [[ -z "$CONSOLE_USER" ]] || [[ "$CONSOLE_USER" == "root" ]]; then
    echo "No user logged in, skipping"
    exit 0
fi

USER_HOME=$(dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory | awk '{print $2}')
NPM_GLOBAL_DIR="$USER_HOME/.npm-global"

# --- Fix gcloud config ownership ---
if [[ -d "$USER_HOME/.config/gcloud" ]]; then
    echo "Fixing gcloud config ownership for $CONSOLE_USER..."
    chown -R "$CONSOLE_USER:staff" "$USER_HOME/.config/gcloud"
    echo "Fixed $USER_HOME/.config/gcloud ownership"
fi

# --- Configure npm global prefix ---
echo "Configuring npm global prefix for $CONSOLE_USER at $NPM_GLOBAL_DIR"

# Create the user's global npm directory
sudo -u "$CONSOLE_USER" mkdir -p "$NPM_GLOBAL_DIR"/{bin,lib}

# Find npm binary via PATH (respects Homebrew shims; allows test stubs)
NPM_BIN=$(command -v npm 2>/dev/null)

if [[ -z "$NPM_BIN" ]]; then
    # npm may not be installed yet — this policy is Once per computer so don't
    # exit 1 here (that would permanently mark it as failed and never retry).
    # Exit 0 so Jamf records a success; the Homebrew Package Installer already
    # configures npm prefix as part of its per-user setup.
    echo "npm not found — skipping (will be configured by homebrew_package_installer when node is installed)"
    exit 0
fi
echo "Using npm at: $NPM_BIN"

NPM_DIR=$(dirname "$NPM_BIN")

# --- Build CA bundle for Node.js SSL ---
CA_BUNDLE="/usr/local/share/ca-certificates/combined-ca-bundle.pem"
if [[ ! -f "$CA_BUNDLE" ]]; then
    echo "Building CA certificate bundle..."
    mkdir -p /usr/local/share/ca-certificates
    security find-certificate -a -p /System/Library/Keychains/SystemRootCertificates.keychain > "$CA_BUNDLE" 2>/dev/null
    security find-certificate -a -p /Library/Keychains/System.keychain >> "$CA_BUNDLE" 2>/dev/null
    chmod 644 "$CA_BUNDLE"
fi

# Environment for all npm commands
NPM_ENV=(PATH="$NPM_DIR:/usr/local/bin:/usr/bin:/bin")
if [[ -f "$CA_BUNDLE" ]]; then
    NPM_ENV+=(NODE_EXTRA_CA_CERTS="$CA_BUNDLE")
fi

# FIX: Use 'env' explicitly to inject array as environment variables.
# Previously: sudo -u "$CONSOLE_USER" "${NPM_ENV[@]}" "$NPM_BIN" ...
# Array elements passed as positional args to sudo may not be treated as
# env var assignments on all macOS/sudo versions. 'env' guarantees injection.
sudo -u "$CONSOLE_USER" env "${NPM_ENV[@]}" "$NPM_BIN" config set prefix "$NPM_GLOBAL_DIR" 2>/dev/null

# Add ~/.npm-global/bin to PATH system-wide via shell profile
PROFILE_SNIPPET='# npm global packages (managed by Jamf)
if [ -d "$HOME/.npm-global/bin" ]; then
  export PATH="$HOME/.npm-global/bin:$PATH"
fi'

# Write to /etc/zprofile so it applies to all zsh login shells
if ! grep -q "npm-global" /etc/zprofile 2>/dev/null; then
    echo "" >> /etc/zprofile
    echo "$PROFILE_SNIPPET" >> /etc/zprofile
    echo "Added ~/.npm-global/bin to PATH in /etc/zprofile"
fi

# --- Install common global npm packages ---
echo "Installing global npm packages for $CONSOLE_USER..."
# FIX: Use 'env' explicitly here too
sudo -u "$CONSOLE_USER" env "${NPM_ENV[@]}" "$NPM_BIN" install -g --prefix "$NPM_GLOBAL_DIR" yarn 2>&1 && \
    echo "yarn installed successfully" || \
    echo "WARNING: yarn install failed"

echo "Done. $CONSOLE_USER can now run 'npm install -g' without admin rights."
exit 0
