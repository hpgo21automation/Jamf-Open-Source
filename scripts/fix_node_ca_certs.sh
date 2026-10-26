#!/bin/bash
# Fix Node.js/npm SSL certificate trust for all users
# Node.js uses its own CA store and doesn't trust the macOS system keychain.
# This exports system-trusted CAs and configures npm/node to use them.

LOG="/var/log/fix_node_ca_certs.log"
CA_BUNDLE="/usr/local/share/ca-certificates/combined-ca-bundle.pem"
CA_DIR="/usr/local/share/ca-certificates"

echo "$(date): Starting Node.js CA certificate fix" | tee -a "$LOG"

# Create output directory
mkdir -p "$CA_DIR"

# Export all trusted certificates from macOS keychains
echo "$(date): Exporting system trusted certificates..." | tee -a "$LOG"

# System root CAs (Apple built-in)
security find-certificate -a -p /System/Library/Keychains/SystemRootCertificates.keychain > "$CA_BUNDLE" 2>/dev/null

# Admin/MDM-installed CAs (corporate certs, etc.)
security find-certificate -a -p /Library/Keychains/System.keychain >> "$CA_BUNDLE" 2>/dev/null

CERT_COUNT=$(grep -c 'BEGIN CERTIFICATE' "$CA_BUNDLE")
echo "$(date): Exported $CERT_COUNT certificates to $CA_BUNDLE" | tee -a "$LOG"

# Set global npm cafile
echo "$(date): Configuring global npmrc..." | tee -a "$LOG"
npm config set -g cafile "$CA_BUNDLE" 2>/dev/null

# Also write to /etc/npmrc as a fallback
echo "cafile=$CA_BUNDLE" > /etc/npmrc
echo "$(date): Wrote /etc/npmrc" | tee -a "$LOG"

# Set NODE_EXTRA_CA_CERTS system-wide for all zsh users
if ! grep -q "NODE_EXTRA_CA_CERTS" /etc/zshenv 2>/dev/null; then
    echo "" >> /etc/zshenv
    echo "# Node.js CA certificates (managed by Jamf)" >> /etc/zshenv
    echo "export NODE_EXTRA_CA_CERTS=\"$CA_BUNDLE\"" >> /etc/zshenv
    echo "$(date): Added NODE_EXTRA_CA_CERTS to /etc/zshenv" | tee -a "$LOG"
else
    echo "$(date): NODE_EXTRA_CA_CERTS already in /etc/zshenv" | tee -a "$LOG"
fi

# Set SSL_CERT_FILE and REQUESTS_CA_BUNDLE for Python
if ! grep -q "SSL_CERT_FILE" /etc/zshenv 2>/dev/null; then
    echo "" >> /etc/zshenv
    echo "# Python CA certificates (managed by Jamf)" >> /etc/zshenv
    echo "export SSL_CERT_FILE=\"$CA_BUNDLE\"" >> /etc/zshenv
    echo "export REQUESTS_CA_BUNDLE=\"$CA_BUNDLE\"" >> /etc/zshenv
    echo "$(date): Added SSL_CERT_FILE and REQUESTS_CA_BUNDLE to /etc/zshenv" | tee -a "$LOG"
else
    echo "$(date): SSL_CERT_FILE already in /etc/zshenv" | tee -a "$LOG"
fi

chmod 644 "$CA_BUNDLE"
echo "$(date): Done. Users need to open a new terminal for changes to take effect." | tee -a "$LOG"
exit 0
