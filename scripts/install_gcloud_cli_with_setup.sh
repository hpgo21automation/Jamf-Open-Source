#!/bin/bash
set -euo pipefail

# Wrapper: installs Google Cloud CLI, fixes Node.js CA certs, fixes home directory permissions.
# Combines install_gcloud_cli.sh + fix_node_ca_certs.sh + fix_home_directory_permissions.sh
# so the policy only needs a single script block (avoids Jamf provider script-ordering drift).

# ============================================================
# STEP 1: Install Google Cloud CLI
# ============================================================

LOG="/var/log/gcloud_install.log"
exec > >(tee -a "$LOG") 2>&1

GCLOUD_SDK_DIR="/usr/local/google-cloud-sdk"
GCLOUD_BIN="$GCLOUD_SDK_DIR/bin/gcloud"

COMPONENTS=(
    "alpha" "anthos-auth" "app-engine-go" "app-engine-python"
    "app-engine-python-extras" "beta" "bigtable" "cbt"
    "cloud-datastore-emulator" "cloud-firestore-emulator" "cloud-run-proxy"
    "cloud-sql-proxy" "config-connector" "docker-credential-gcr"
    "enterprise-certificate-proxy" "gke-gcloud-auth-plugin" "istioctl"
    "kpt" "kubectl" "kubectl-oidc" "kustomize" "local-extract"
    "log-streaming" "minikube" "nomos" "package-go-module" "pkg"
    "pubsub-emulator" "skaffold" "spanner-cli" "terraform-tools"
)

fix_gcloud_permissions() {
    echo "=== FIXING GCLOUD PERMISSIONS ==="
    chmod -R 775 "$GCLOUD_SDK_DIR" 2>/dev/null || true
    chgrp -R admin "$GCLOUD_SDK_DIR" 2>/dev/null || true
}

# Ensure the console user owns their ~/.config/gcloud tree. Re-running gcloud
# commands as root (from this script) can leave root-owned files under the
# user's config dir, which then breaks `gcloud init` / `gcloud auth login`
# with EACCES when the user runs it as themselves.
fix_user_gcloud_config_ownership() {
    local console_user
    console_user=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk '/Name :/ && ! /loginwindow/ { print $3 }')
    if [[ -z "$console_user" ]] || [[ "$console_user" == "root" ]]; then
        return 0
    fi
    local user_home
    user_home=$(/usr/bin/dscl . -read "/Users/$console_user" NFSHomeDirectory | awk '{print $2}')
    local user_group
    user_group=$(/usr/bin/dscl . -search /Groups PrimaryGroupID "$(/usr/bin/id -g "$console_user")" | /usr/bin/awk 'NR==1{print $1}')
    [[ -z "$user_group" ]] && user_group="staff"
    if [[ -d "$user_home/.config/gcloud" ]]; then
        chown -R "${console_user}:${user_group}" "$user_home/.config/gcloud" 2>/dev/null || true
        echo "Normalized ownership of $user_home/.config/gcloud to ${console_user}:${user_group}"
    fi
}

install_gcloud_components() {
    echo "========================================"
    echo "INSTALLING ALL COMPONENTS"
    echo "========================================"
    local FAILED=() INSTALLED=()
    for component in "${COMPONENTS[@]}"; do
        if "$GCLOUD_BIN" components install "$component" --quiet 2>&1; then
            INSTALLED+=("$component")
        else
            FAILED+=("$component")
            echo "FAILED: $component"
        fi
    done
    echo "Installed: ${#INSTALLED[@]} | Failed: ${#FAILED[@]}"
    # Use an explicit `if` here — a bare `[[ ... ]] && echo` returns the test's
    # exit code (1) when there are no failures, and under `set -e` that
    # propagates out of the function and kills the script.
    if (( ${#FAILED[@]} > 0 )); then
        echo "Failed: ${FAILED[*]}"
    fi
}

echo "========================================"
echo "$(date): Starting Google Cloud CLI installation"
echo "========================================"

if [[ -x "$GCLOUD_BIN" ]] && "$GCLOUD_BIN" version &>/dev/null; then
    echo "Google Cloud CLI already installed: $($GCLOUD_BIN version 2>/dev/null | head -1)"
    fix_gcloud_permissions
    install_gcloud_components
    fix_gcloud_permissions
    fix_user_gcloud_config_ownership
    echo "Existing installation updated"
else
    [[ -d "$GCLOUD_SDK_DIR" ]] && rm -rf "$GCLOUD_SDK_DIR"

    ARCH=$(uname -m)
    # Google removed the *-bundled-python tarballs from the rapid channel
    # (they now 404). Use the plain tarballs and rely on CLOUDSDK_PYTHON,
    # which is set above to a probed/installed Python 3.10+ interpreter.
    if [[ "$ARCH" == "arm64" ]]; then
        PACKAGE_URL="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-darwin-arm.tar.gz"
    else
        PACKAGE_URL="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-darwin-x86_64.tar.gz"
    fi

    # gcloud SDK bootstrap (install.py) uses Python 3.10+ `match` syntax.
    # macOS ships Python 3.9 at /usr/bin/python3, which crashes the bootstrap.
    # Probe known locations for a usable Python; install python.org's pkg if none found.
    find_modern_python() {
        for candidate in \
            /Library/Frameworks/Python.framework/Versions/3.13/bin/python3 \
            /Library/Frameworks/Python.framework/Versions/3.12/bin/python3 \
            /Library/Frameworks/Python.framework/Versions/3.11/bin/python3 \
            /opt/homebrew/bin/python3.13 \
            /opt/homebrew/bin/python3.12 \
            /opt/homebrew/bin/python3.11 \
            /opt/homebrew_srv/bin/python3.13 \
            /opt/homebrew_srv/bin/python3.12 \
            /opt/homebrew_srv/bin/python3.11 \
            /usr/local/bin/python3.13 \
            /usr/local/bin/python3.12 \
            /usr/local/bin/python3.11; do
            if [[ -x "$candidate" ]] && "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)' 2>/dev/null; then
                echo "$candidate"
                return 0
            fi
        done
        return 1
    }

    PYTHON_BIN=$(find_modern_python || true)
    if [[ -z "$PYTHON_BIN" ]]; then
        echo "No Python >= 3.10 found; installing python.org Python 3.12"
        PY_PKG="/tmp/python-3.12.8-macos11.pkg"
        curl -sSLf -o "$PY_PKG" "https://www.python.org/ftp/python/3.12.8/python-3.12.8-macos11.pkg"
        /usr/sbin/installer -pkg "$PY_PKG" -target /
        rm -f "$PY_PKG"
        PYTHON_BIN="/Library/Frameworks/Python.framework/Versions/3.12/bin/python3"
    fi
    echo "Using Python: $PYTHON_BIN ($("$PYTHON_BIN" --version 2>&1))"
    export CLOUDSDK_PYTHON="$PYTHON_BIN"

    cd /tmp
    curl -sSLf -o gcloud-cli.tar.gz "$PACKAGE_URL"
    tar -xzf gcloud-cli.tar.gz
    [[ -d "$GCLOUD_SDK_DIR" ]] && rm -rf "$GCLOUD_SDK_DIR"
    mv google-cloud-sdk /usr/local/

    # The plain tarball ships no bundled Python, so CLOUDSDK_PYTHON (set above
    # to a probed/installed 3.10+ interpreter) is used. macOS system Python
    # (3.9) lacks the `match` syntax used by current gcloud sources, so we must
    # not fall back to it. If a future tarball does ship a bundled Python,
    # prefer it.
    BUNDLED_PYTHON="$GCLOUD_SDK_DIR/platform/bundledpythonunix/bin/python3"
    if [[ -x "$BUNDLED_PYTHON" ]]; then
        export CLOUDSDK_PYTHON="$BUNDLED_PYTHON"
    fi

    "$GCLOUD_SDK_DIR/install.sh" --quiet --path-update=true

    ln -sf "$GCLOUD_SDK_DIR/bin/gcloud"  /usr/local/bin/gcloud
    ln -sf "$GCLOUD_SDK_DIR/bin/gsutil"  /usr/local/bin/gsutil
    ln -sf "$GCLOUD_SDK_DIR/bin/bq"      /usr/local/bin/bq

    fix_gcloud_permissions
    install_gcloud_components
    fix_gcloud_permissions

    for tool in kubectl minikube skaffold kustomize istioctl kpt nomos cbt gke-gcloud-auth-plugin docker-credential-gcr; do
        [[ -x "$GCLOUD_SDK_DIR/bin/$tool" ]] && ln -sf "$GCLOUD_SDK_DIR/bin/$tool" "/usr/local/bin/$tool"
    done

    fix_user_gcloud_config_ownership

    rm -f /tmp/gcloud-cli.tar.gz

    if command -v gcloud &>/dev/null; then
        echo "Installation successful: $(gcloud version 2>/dev/null | head -1)"
    else
        echo "ERROR: gcloud not found after install"
        exit 1 # jamf-ci: exit1-intentional
    fi
fi

# ============================================================
# STEP 2: Fix Node.js CA certificates
#
# `set -euo pipefail` is in effect for STEP 1 and STEP 2. Several commands
# below can legitimately return non-zero on healthy systems and must not
# abort the policy run:
#   - `security find-certificate` on a locked/empty keychain
#   - `grep -c` returns 1 when no matches are found (e.g. empty bundle file)
#   - `npm config set` fails when npm is not yet installed on the device
# These are guarded with `|| true` (or `|| echo 0` for the cert count) so
# the policy step can complete even when those tools/keychains are unavailable.
# Root cause of recurring failures on device 19: one of these commands was
# aborting the script under `set -e` before STEP 3 could run.
# ============================================================

NODE_LOG="/var/log/fix_node_ca_certs.log"
CA_BUNDLE="/usr/local/share/ca-certificates/combined-ca-bundle.pem"
CA_DIR="/usr/local/share/ca-certificates"

echo "$(date): Starting Node.js CA certificate fix" | tee -a "$NODE_LOG"
mkdir -p "$CA_DIR"

security find-certificate -a -p /System/Library/Keychains/SystemRootCertificates.keychain > "$CA_BUNDLE" 2>/dev/null || true
security find-certificate -a -p /Library/Keychains/System.keychain >> "$CA_BUNDLE" 2>/dev/null || true

CERT_COUNT=$(grep -c 'BEGIN CERTIFICATE' "$CA_BUNDLE" 2>/dev/null || echo 0)
echo "$(date): Exported $CERT_COUNT certificates to $CA_BUNDLE" | tee -a "$NODE_LOG"

npm config set -g cafile "$CA_BUNDLE" 2>/dev/null || true
echo "cafile=$CA_BUNDLE" > /etc/npmrc

if ! grep -q "NODE_EXTRA_CA_CERTS" /etc/zshenv 2>/dev/null; then
    printf '\n# Node.js CA certificates (managed by Jamf)\nexport NODE_EXTRA_CA_CERTS="%s"\n' "$CA_BUNDLE" >> /etc/zshenv
fi
if ! grep -q "SSL_CERT_FILE" /etc/zshenv 2>/dev/null; then
    printf '\n# Python CA certificates (managed by Jamf)\nexport SSL_CERT_FILE="%s"\nexport REQUESTS_CA_BUNDLE="%s"\n' "$CA_BUNDLE" "$CA_BUNDLE" >> /etc/zshenv
fi

chmod 644 "$CA_BUNDLE"
echo "$(date): Node.js CA cert fix complete" | tee -a "$NODE_LOG"

# ============================================================
# STEP 3: Fix home directory permissions
# ============================================================

# Not using set -e here — chown on a large home dir will hit protected files
set +e

log_home() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"; /usr/bin/logger -t "FixHomePermissions" "$1"; }

CURRENT_USER=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk '/Name :/ && ! /loginwindow/ { print $3 }')
if [[ -z "$CURRENT_USER" ]] || [[ "$CURRENT_USER" == "root" ]]; then
    log_home "No valid user logged in, skipping home directory fix"
    exit 0
fi

HOME_DIR=$(/usr/bin/dscl . -read "/Users/$CURRENT_USER" NFSHomeDirectory | awk '{print $2}')
PRIMARY_GID=$(/usr/bin/id -g "$CURRENT_USER")
USER_GROUP=$(/usr/bin/dscl . -search /Groups PrimaryGroupID "$PRIMARY_GID" | /usr/bin/awk 'NR==1{print $1}')
[[ -z "$USER_GROUP" ]] && USER_GROUP="staff"

log_home "====== Starting Home Directory Permission Fix ======"
log_home "User: $CURRENT_USER | Home: $HOME_DIR | Group: $USER_GROUP"

WRONG_OWNER=$(/usr/bin/find "$HOME_DIR" ! -user "$CURRENT_USER" 2>/dev/null | /usr/bin/wc -l | tr -d ' ')
WRONG_GROUP=$(/usr/bin/find "$HOME_DIR" ! -group "$USER_GROUP" 2>/dev/null | /usr/bin/wc -l | tr -d ' ')

if [[ "$WRONG_OWNER" -eq 0 ]] && [[ "$WRONG_GROUP" -eq 0 ]]; then
    log_home "Permissions already correct, no changes needed"
else
    /usr/bin/sudo -u "$CURRENT_USER" /usr/bin/osascript -e "display notification \"Fixing home directory permissions...\" with title \"IT Self Service\"" 2>/dev/null || true
    /usr/sbin/chown -R "${CURRENT_USER}:${USER_GROUP}" "$HOME_DIR" 2>/dev/null || true
    /bin/chmod 750 "$HOME_DIR"
    log_home "SUCCESS: Ownership and permissions updated"
    /usr/bin/sudo -u "$CURRENT_USER" /usr/bin/osascript -e "display notification \"Home directory permissions fixed.\" with title \"IT Self Service\"" 2>/dev/null || true
fi

log_home "====== Home Directory Permission Fix Complete ======"
exit 0
