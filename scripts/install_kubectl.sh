#!/bin/bash
# Install kubectl

# Check if already installed
if command -v kubectl &>/dev/null; then
    echo "kubectl already installed: $(kubectl version --client 2>/dev/null | head -n 1)"
    exit 0
fi

# Determine architecture
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    KUBECTL_ARCH="arm64"
else
    KUBECTL_ARCH="amd64"
fi

# Get latest stable version
KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)

if [[ -z "$KUBECTL_VERSION" ]]; then
    echo "Failed to get latest kubectl version"
    exit 1
fi

echo "Installing kubectl ${KUBECTL_VERSION} for ${KUBECTL_ARCH}..."

# Download kubectl
cd /tmp || exit 1
curl -sLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/darwin/${KUBECTL_ARCH}/kubectl"

# Verify download
if [[ ! -f /tmp/kubectl ]]; then
    echo "Download failed"
    exit 1
fi

# Make executable and move to path
chmod +x /tmp/kubectl
mv /tmp/kubectl /usr/local/bin/kubectl

# Verify
if command -v kubectl &>/dev/null; then
    echo "kubectl installed successfully: $(kubectl version --client 2>/dev/null | head -n 1)"
    exit 0
else
    echo "Installation failed"
    exit 1
fi