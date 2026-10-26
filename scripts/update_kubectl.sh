#!/bin/bash
# Update kubectl to latest version

ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    KUBECTL_ARCH="arm64"
else
    KUBECTL_ARCH="amd64"
fi

# Get latest stable version
KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)

if [[ -z "$KUBECTL_VERSION" ]]; then
    echo "Failed to get latest kubectl version" >&2
    # jamf-ci: exit1-intentional
    exit 1
fi

# Get current version if installed
CURRENT_VERSION=""
if command -v kubectl &>/dev/null; then
    CURRENT_VERSION=$(kubectl version --client -o yaml 2>/dev/null | grep gitVersion | awk '{print $2}')
else
    echo "kubectl not installed, skipping update"
    exit 0
fi

if [[ "$CURRENT_VERSION" == "$KUBECTL_VERSION" ]]; then
    echo "kubectl already at latest version: $KUBECTL_VERSION"
    exit 0
fi

echo "Updating kubectl from $CURRENT_VERSION to $KUBECTL_VERSION..."

cd /tmp || { echo "Failed to cd to /tmp" >&2; exit 1; }
curl -sLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/darwin/${KUBECTL_ARCH}/kubectl"

if [[ ! -f /tmp/kubectl ]]; then
    echo "Download failed" >&2
    exit 1
fi

chmod +x /tmp/kubectl
mv /tmp/kubectl /usr/local/bin/kubectl

echo "kubectl updated to $(kubectl version --client -o yaml 2>/dev/null | grep gitVersion | awk '{print $2}')"
exit 0