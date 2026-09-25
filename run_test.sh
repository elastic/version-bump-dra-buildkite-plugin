#!/bin/bash
set -euo pipefail

# Create a temporary directory for BATS and plugins
BATS_ROOT=$(mktemp -d)
BATS_PLUGIN_PATH="${BATS_ROOT}/plugins"

# Cleanup on exit
trap 'rm -rf "${BATS_ROOT}"' EXIT

mkdir -p "${BATS_PLUGIN_PATH}"

# Check if curl and jq are available
if ! command -v curl &> /dev/null; then
    echo "Error: curl is required but not installed"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed"
    exit 1
fi

# Install BATS 1.13.0 if not already installed
if [[ ! -f "${BATS_ROOT}/bin/bats" ]]; then
    echo "Installing BATS 1.13.0..."
    curl -sSL https://github.com/bats-core/bats-core/archive/v1.13.0.tar.gz -o /tmp/bats-core.tgz
    mkdir -p /tmp/bats-core-install
    tar -zxf /tmp/bats-core.tgz -C /tmp/bats-core-install --strip 1
    /tmp/bats-core-install/install.sh "${BATS_ROOT}"
    rm -rf /tmp/bats-core.tgz /tmp/bats-core-install
    echo "✓ BATS installed"
else
    echo "✓ BATS already installed"
fi

# Install bats-support
if [[ ! -d "${BATS_PLUGIN_PATH}/bats-support" ]]; then
    echo "Installing bats-support..."
    mkdir -p "${BATS_PLUGIN_PATH}/bats-support"
    curl -sSL https://github.com/bats-core/bats-support/archive/v0.3.0.tar.gz -o /tmp/bats-support.tgz
    tar -zxf /tmp/bats-support.tgz -C "${BATS_PLUGIN_PATH}/bats-support" --strip 1
    rm -rf /tmp/bats-support.tgz
    echo "✓ bats-support installed"
else
    echo "✓ bats-support already installed"
fi

# Install bats-assert
if [[ ! -d "${BATS_PLUGIN_PATH}/bats-assert" ]]; then
    echo "Installing bats-assert..."
    mkdir -p "${BATS_PLUGIN_PATH}/bats-assert"
    curl -sSL https://github.com/bats-core/bats-assert/archive/v2.1.0.tar.gz -o /tmp/bats-assert.tgz
    tar -zxf /tmp/bats-assert.tgz -C "${BATS_PLUGIN_PATH}/bats-assert" --strip 1
    rm -rf /tmp/bats-assert.tgz
    echo "✓ bats-assert installed"
else
    echo "✓ bats-assert already installed"
fi

# Install bats-file
if [[ ! -d "${BATS_PLUGIN_PATH}/bats-file" ]]; then
    echo "Installing bats-file..."
    mkdir -p "${BATS_PLUGIN_PATH}/bats-file"
    curl -sSL https://github.com/bats-core/bats-file/archive/v0.4.0.tar.gz -o /tmp/bats-file.tgz
    tar -zxf /tmp/bats-file.tgz -C "${BATS_PLUGIN_PATH}/bats-file" --strip 1
    rm -rf /tmp/bats-file.tgz
    echo "✓ bats-file installed"
else
    echo "✓ bats-file already installed"
fi

# Install bats-mock (buildkite fork)
if [[ ! -d "${BATS_PLUGIN_PATH}/bats-mock" ]]; then
    echo "Installing bats-mock (buildkite fork)..."
    mkdir -p "${BATS_PLUGIN_PATH}/bats-mock"
    curl -sSL https://github.com/buildkite-plugins/bats-mock/archive/v2.2.0.tar.gz -o /tmp/bats-mock.tgz
    tar -zxf /tmp/bats-mock.tgz -C "${BATS_PLUGIN_PATH}/bats-mock" --strip 1
    rm -rf /tmp/bats-mock.tgz
    echo "✓ bats-mock installed"
else
    echo "✓ bats-mock already installed"
fi

# Create load.bash that sources all plugins (mimics the Docker container)
echo "Creating load.bash..."
cat > "${BATS_PLUGIN_PATH}/load.bash" <<EOF
source "${BATS_PLUGIN_PATH}/bats-assert/load.bash"
source "${BATS_PLUGIN_PATH}/bats-mock/stub.bash"
source "${BATS_PLUGIN_PATH}/bats-file/load.bash"
source "${BATS_PLUGIN_PATH}/bats-support/load.bash"
EOF
echo "✓ load.bash created"

# Export environment variable so tests can find the plugins
export BATS_PLUGIN_PATH

# Add BATS to PATH
export PATH="${BATS_ROOT}/bin:${PATH}"

echo ""
echo "--- :test_tube: Running BATS tests"
echo "BATS version: $(bats --version)"
echo "BATS_PLUGIN_PATH: ${BATS_PLUGIN_PATH}"
echo ""

# Run the tests
bats tests/
